#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_details.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.09
# Version....: v0.2.0
# Purpose....: Show/export detailed info for Oracle Data Safe target databases
#              for given target names/OCIDs or all targets in a compartment.
#              Output formats: table | json | csv.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_details.conf
#              > DEFAULT_CONF > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.09 oehrli - migrate to v0.2.0 framework pattern
# ------------------------------------------------------------------------------

# --- Code defaults (lowest precedence; overridden by .env/CONF/CLI) ----------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"

: "${COMPARTMENT:=}"                 # name or OCID
: "${TARGETS:=}"                     # CSV names/OCIDs (overrides compartment mode)
: "${STATE_FILTERS:=ACTIVE,NEEDS_ATTENTION}"# CSV lifecycle states when scanning compartment
: "${RAW_SINCE_DATE:=}"              # e.g. 2025-01-01 or -2w/-3m (normalized)

: "${OUTPUT_TYPE:=csv}"              # csv | json | table
: "${OUTPUT_FILE:=./datasafe_target_details.csv}"

# shellcheck disable=SC2034  # DEFAULT_CONF may be used for configuration loading in future
DEFAULT_CONF="${SCRIPT_ETC_DIR:-./etc}/ds_target_details.conf"

# Runtime
SINCE_DATE=""
COMP_OCID=""
COMP_NAME=""
# shellcheck disable=SC2034  # TARGET_LIST may be used for target resolution in future
TARGET_LIST=()
RESOLVED_TARGETS=()
DETAILS_JSON='[]'
exported_count=0

# --- Minimal bootstrap: ensure SCRIPT_BASE and libraries ----------------------
if [[ -z "${SCRIPT_BASE:-}" || -z "${SCRIPT_LIB_DIR:-}" ]]; then
  _SRC="${BASH_SOURCE[0]}"
  SCRIPT_BASE="$(cd "$(dirname "${_SRC}")/.." >/dev/null 2>&1 && pwd)"
  SCRIPT_LIB_DIR="${SCRIPT_BASE}/lib"
  unset _SRC
fi

# Load the odb_datasafe v0.2.0 framework
if [[ -r "${SCRIPT_LIB_DIR}/ds_lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_LIB_DIR}/ds_lib.sh" || { echo "ERROR: ds_lib.sh failed to load." >&2; exit 1; }
else
  echo "ERROR: ds_lib.sh not found (tried: ${SCRIPT_LIB_DIR}/ds_lib.sh)" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Function....: Usage
# Purpose.....: Display command-line usage instructions and exit
# ------------------------------------------------------------------------------
Usage() {
  local exit_code="${1:-0}"
  
  cat << EOF

Usage:
  ds_target_details.sh (-T <CSV> | -c <OCID|NAME>) [options]

Show detailed info for Data Safe target databases. Either provide explicit 
targets (-T) or scan a compartment (-c). If both are provided, -T takes precedence.

Target selection (choose one):
  -T, --targets <LIST>            Comma-separated target names or OCIDs
  (or) use lifecycle-state filtering (default: ACTIVE,NEEDS_ATTENTION):
  -s, --state <LIST>              Comma-separated states (e.g. NEEDS_ATTENTION,ACTIVE)

Scope:
  -c, --compartment <OCID|NAME>   Compartment OCID or name (env: COMPARTMENT/COMP_OCID)
  -D, --since-date <STR>          Only targets created >= date
                                  (YYYY-MM-DD, RFC3339, or -2d/-1w/-3m)

Output:
  -O, --output-type csv|json|table Output format (default: ${OUTPUT_TYPE})
  -o, --output <file>             Output CSV path (for csv; default: ${OUTPUT_FILE})

OCI CLI:
      --oci-config <file>         OCI CLI config file (default: ${OCI_CLI_CONFIG_FILE})
      --oci-profile <name>        OCI CLI profile     (default: ${OCI_CLI_PROFILE})

Logging / generic:
  -l, --log-file <file>           Write logs to <file>
  -v, --verbose                   Set log level to INFO
  -d, --debug                     Set log level to DEBUG
  -t, --trace                     Set log level to TRACE
  -q, --quiet                     Suppress INFO/DEBUG/TRACE stdout
      --log-level <LEVEL>         ERROR|WARN|INFO|DEBUG|TRACE
  -h, --help                      Show this help and exit

CSV columns:
  datasafe_ocid,display_name,lifecycle,created_at,infra_type,target_type,
  host,port,service_name,connector_name,compartment_id,cluster,cdb,pdb

Examples:
  ds_target_details.sh -T exa118r05c15_cdb09a15_HRPDB,ocid1.datasafetargetdatabase...
  ds_target_details.sh -c my-compartment -O json
  ds_target_details.sh -c test-compartment -s ACTIVE -O table

EOF
  die "${exit_code}" ""
}

# ------------------------------------------------------------------------------
# Function....: parse_args
# Purpose.....: Parse script-specific arguments from REM_ARGS
# ------------------------------------------------------------------------------
parse_args() {
  local -a args=("${REM_ARGS[@]}")
  POSITIONAL=()

  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
      -T|--targets)               TARGETS="${args[++i]:-}" ;;
      -s|--state)                 STATE_FILTERS="${args[++i]:-}" ;;
      -D|--since-date)            RAW_SINCE_DATE="${args[++i]:-}" ;;
      -c|--compartment)           COMPARTMENT="${args[++i]:-}" ;;
      -O|--output-type)           OUTPUT_TYPE="${args[++i]:-}" ;;
      -o|--output)                OUTPUT_FILE="${args[++i]:-}" ;;
      --oci-config)               OCI_CLI_CONFIG_FILE="${args[++i]:-}" ;;
      --oci-profile)              OCI_CLI_PROFILE="${args[++i]:-}" ;;
      -h|--help)                  Usage 0 ;;
      --)                         ((i++)); while ((i < ${#args[@]})); do POSITIONAL+=("${args[i++]}"); done ;;
      -*)                         log_error "Unknown option: ${args[i]}"; Usage 2 ;;
      *)                          POSITIONAL+=("${args[i]}") ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# Function....: preflight_checks
# Purpose.....: Validate/normalize inputs and resolve target list → OCIDs
# ------------------------------------------------------------------------------
preflight_checks() {
  # Normalize since-date
  SINCE_DATE=""
  if [[ -n "${RAW_SINCE_DATE}" ]]; then
    # Simple date normalization (could be enhanced)
    if [[ "${RAW_SINCE_DATE}" =~ ^-[0-9]+[dwm]$ ]]; then
      # Relative date format (-2d, -1w, -3m)
      local amount="${RAW_SINCE_DATE:1:-1}"
      local unit="${RAW_SINCE_DATE: -1}"
      case "${unit}" in
        d) SINCE_DATE="$(date -u -v-"${amount}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${amount} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")" ;;
        w) SINCE_DATE="$(date -u -v-"$((amount * 7))"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$((amount * 7)) days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")" ;;
        m) SINCE_DATE="$(date -u -v-"$((amount * 30))"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$((amount * 30)) days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")" ;;
      esac
    else
      SINCE_DATE="${RAW_SINCE_DATE}"
    fi
  fi

  # Build target list from -T and positionals
  ds_build_target_list TARGET_LIST "${TARGETS:-}" POSITIONAL

  # Validate/augment from compartment + filters
  ds_validate_and_fill_targets \
    TARGET_LIST "${COMPARTMENT:-}" "${STATE_FILTERS:-}" "${SINCE_DATE:-}" \
    COMP_OCID COMP_NAME

  # Resolve names → OCIDs
  ds_resolve_targets_to_ocids TARGET_LIST RESOLVED_TARGETS || \
    die 1 "Failed to resolve targets to OCIDs."

  log_info "Targets selected for details: ${#RESOLVED_TARGETS[@]}"

  if [[ ${#RESOLVED_TARGETS[@]} -eq 0 ]]; then
    log_warn "No targets found matching criteria"
    die 0 "No targets to process"
  fi

  # Output type sanity
  OUTPUT_TYPE="${OUTPUT_TYPE,,}"
  case "${OUTPUT_TYPE}" in
    csv|json|table) : ;;
    *) die 2 "Unsupported --output-type '${OUTPUT_TYPE}'. Use csv|json|table." ;;
  esac

  # Ensure CSV path if csv mode
  if [[ "${OUTPUT_TYPE}" == "csv" ]]; then
    mkdir -p "$(dirname "${OUTPUT_FILE}")" 2>/dev/null || true
  fi
}

# --- Steps --------------------------------------------------------------------

# Step 1: Build connector mapping for the compartment (for connector name resolution)
step_build_connector_map() {
  declare -gA CONNECTOR_MAP=()
  
  [[ -z "${COMP_OCID}" ]] && return 0
  
  log_debug "Building connector mapping for compartment: ${COMP_NAME}"
  
  local connectors_json
  connectors_json="$(oci data-safe on-premises-connector list \
    --compartment-id "${COMP_OCID}" \
    --config-file "${OCI_CLI_CONFIG_FILE}" \
    --profile "${OCI_CLI_PROFILE}" \
    --all \
    --raw-output 2>/dev/null)" || return 0

  while IFS=$'\t' read -r ocid name; do
    [[ -n "${ocid}" ]] && CONNECTOR_MAP["${ocid}"]="${name:-Unknown}"
  done < <(echo "${connectors_json}" | jq -r '.data[]? | [(.id // ""), (."display-name" // .displayName // "")] | @tsv')
  
  log_debug "Mapped ${#CONNECTOR_MAP[@]} connectors"
}

# Step 2: Collect per-target details into DETAILS_JSON (array of enriched objects)
step_collect_details() {
  log_info "Collecting target details..."
  DETAILS_JSON='[]'
  local processed=0 failed=0

  for target_ocid in "${RESOLVED_TARGETS[@]}"; do
    # Resolve identity
    local target_name
    target_name="$(ds_resolve_target_name "${target_ocid}" 2>/dev/null || echo "${target_ocid}")"

    log_debug "Processing: ${target_name}"

    # Fetch target details
    local target_json
    target_json="$(oci data-safe target-database get \
      --target-database-id "${target_ocid}" \
      --config-file "${OCI_CLI_CONFIG_FILE}" \
      --profile "${OCI_CLI_PROFILE}" \
      --raw-output 2>/dev/null)" || {
      log_error "Failed to get details for ${target_name}"
      ((failed++))
      continue
    }

    # Extract fields from the response
    local data disp lcst created infra ttype host port svc compid conn_ocid conn_name
    data="$(echo "${target_json}" | jq -r '.data')"
    disp="$(echo "${data}" | jq -r '."display-name" // .displayName // empty')"
    lcst="$(echo "${data}" | jq -r '."lifecycle-state" // empty' | tr '[:lower:]' '[:upper:]')"
    created="$(echo "${data}" | jq -r '."time-created" // empty')"
    infra="$(echo "${data}" | jq -r '."infrastructure-type" // empty')"
    ttype="$(echo "${data}" | jq -r '."target-database-type" // empty')"
    host="$(echo "${data}" | jq -r '."database-details"."host-name" // empty')"
    port="$(echo "${data}" | jq -r '."database-details"."listener-port" // empty | tostring')"
    svc="$(echo "${data}" | jq -r '."database-details"."service-name" // empty')"
    compid="$(echo "${data}" | jq -r '."compartment-id" // empty')"

    # Connector OCID → name (if any)
    conn_ocid="$(echo "${data}" | jq -r '.["associated-resource-ids"]?[]? | select(startswith("ocid1.datasafeonpremconnector")) // empty' | head -n1)"
    if [[ -n "${conn_ocid}" && -n "${CONNECTOR_MAP["${conn_ocid}"]:-}" ]]; then
      conn_name="${CONNECTOR_MAP["${conn_ocid}"]}"
    elif [[ -n "${conn_ocid}" ]]; then
      conn_name="Unknown"
    else
      conn_name="N/A"
    fi

    # Derive cluster/cdb/pdb from display-name (best-effort parsing)
    local cluster cdb pdb
    if [[ "${disp}" =~ ^([^_]+)_([^_]+)_(.+)$ ]]; then
      cluster="${BASH_REMATCH[1]}"
      cdb="${BASH_REMATCH[2]}"  
      pdb="${BASH_REMATCH[3]}"
    elif [[ "${disp}" =~ ^([^_]+)_(.+)$ ]]; then
      cluster=""
      cdb="${BASH_REMATCH[1]}"
      pdb="${BASH_REMATCH[2]}"
    else
      cluster=""
      cdb="${disp}"
      pdb=""
    fi

    # Build record
    local record
    record="$(jq -n \
      --arg ocid "${target_ocid}" \
      --arg disp "${disp}" \
      --arg lcst "${lcst}" \
      --arg created "${created}" \
      --arg infra "${infra}" \
      --arg ttype "${ttype}" \
      --arg host "${host}" \
      --arg port "${port}" \
      --arg svc "${svc}" \
      --arg conn "${conn_name}" \
      --arg comp "${compid}" \
      --arg cluster "${cluster}" \
      --arg cdb "${cdb}" \
      --arg pdb "${pdb}" \
      '{
        datasafe_ocid: $ocid,
        display_name: $disp,
        lifecycle: $lcst,
        created_at: $created,
        infra_type: $infra,
        target_type: $ttype,
        host: $host,
        port: $port,
        service_name: $svc,
        connector_name: $conn,
        compartment_id: $comp,
        cluster: $cluster,
        cdb: $cdb,
        pdb: $pdb
      }')"

    DETAILS_JSON="$(echo "${DETAILS_JSON}" | jq -c --argjson row "${record}" '. + [$row]')"
    ((processed++))
  done

  exported_count="${processed}"
  log_info "Collected details for ${processed} targets (${failed} failed)"
}

# Step 3: Emit output (json | table | csv)
step_emit_output() {
  case "${OUTPUT_TYPE}" in
    json)
      echo "${DETAILS_JSON}" | jq .
      ;;
    table)
      # If no rows, say so and exit early
      if [[ "${DETAILS_JSON}" == "[]" ]]; then
        log_info "No target details to display"
        return 0
      fi
      
      local i=0
      echo "${DETAILS_JSON}" | jq -r '
        .[] |
        [
          (.display_name    // ""),
          (.datasafe_ocid   // ""),
          (.lifecycle       // ""),
          (.created_at      // ""),
          (.infra_type      // ""),
          (.target_type     // ""),
          (.host            // ""),
          ((.port // "") | tostring),
          (.service_name    // ""),
          (.connector_name  // ""),
          (.compartment_id  // ""),
          (.cluster         // ""),
          (.cdb             // ""),
          (.pdb             // "")
        ] | @tsv
      ' | while IFS=$'\t' read -r \
        disp ocid lifecycle created infra ttype host port svc conn comp cluster cdb pdb; do
        ((i+=1))
        printf "\n"
        printf "== Target %d ======================================================\n" "$i"
        printf "Display Name   : %s\n" "${disp}"
        printf "OCID           : %s\n" "${ocid}"
        printf "Lifecycle      : %s\n" "${lifecycle}"
        printf "Created        : %s\n" "${created}"
        printf "Infra/Type     : %s / %s\n" "${infra}" "${ttype}"
        printf "Connection     : %s@%s:%s (via %s)\n" "${host}" "${host}" "${port}" "${conn}"
        printf "Service Name   : %s\n" "${svc}"
        printf "Compartment    : %s\n" "${comp}"
        printf "Cluster/CDB/PDB: %s / %s / %s\n" "${cluster}" "${cdb}" "${pdb}"
      done
      printf "\n"
      ;;
    csv|*)
      {
        echo 'datasafe_ocid,display_name,lifecycle,created_at,infra_type,target_type,host,port,service_name,connector_name,compartment_id,cluster,cdb,pdb'
        echo "${DETAILS_JSON}" | jq -r '.[] | [
          .datasafe_ocid,
          .display_name,
          .lifecycle,
          .created_at,
          .infra_type,
          .target_type,
          .host,
          (.port|tostring),
          .service_name,
          .connector_name,
          .compartment_id,
          .cluster,
          .cdb,
          .pdb
        ] | @csv'
      } > "${OUTPUT_FILE}"
      
      log_info "Wrote ${exported_count} target details to ${OUTPUT_FILE}"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Function....: run_details
# Purpose.....: Orchestrate the steps
# ------------------------------------------------------------------------------
run_details() {
  step_build_connector_map
  step_collect_details
  step_emit_output
  die 0 "Target details collection completed"
}

# ------------------------------------------------------------------------------
# Function....: main
# Purpose.....: Entry point
# ------------------------------------------------------------------------------
main() {
  init_script_env "$@"   # standardized init per odb_datasafe framework
  parse_args
  preflight_checks
  run_details
}

# --- Entry point --------------------------------------------------------------
main "$@"