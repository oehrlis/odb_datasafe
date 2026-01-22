#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: ds_target_connect_details.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.10
# Version....: v0.5.3
# Purpose....: Display connection details for Oracle Data Safe target database.
#              Fetches target info, resolves hosts, and shows connection strings,
#              ports, service names, and credential information.
#              Output formats: table | json.
# Requires...: bash (>=4), oci, jq, lib/ds_lib.sh
# Notes......: Config precedence → CLI > etc/ds_target_connect_details.conf
#              > DEFAULT_CONF > .env > code
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.10 oehrli - rewrite to v0.2.0 framework pattern (simplified)
# ------------------------------------------------------------------------------

# --- Code defaults (lowest precedence; overridden by .env/CONF/CLI) ----------
: "${OCI_CLI_CONFIG_FILE:=${HOME}/.oci/config}"
: "${OCI_CLI_PROFILE:=DEFAULT}"

: "${COMPARTMENT:=}"      # name or OCID (used for target name resolution)
: "${TARGET:=}"           # target name or OCID (mandatory)
: "${OUTPUT_TYPE:=table}" # table | json

# shellcheck disable=SC2034  # DEFAULT_CONF may be used for configuration loading in future
DEFAULT_CONF="${SCRIPT_ETC_DIR:-./etc}/ds_target_connect_details.conf"

# Runtime globals for target connection details
COMP_OCID=""
COMP_NAME=""
TARGET_OCID=""
TARGET_NAME=""

# Target details
TGT_ID=""
TGT_NAME=""
TGT_DESCRIPTION=""
TGT_STATUS=""
TGT_DETAILS=""
TGT_COMP_OCID=""
TGT_COMP_NAME=""
TGT_CONN_TYPE=""
TGT_ONPREM_OCID=""
TGT_ONPREM_NAME=""
TGT_FREEFORM_TAGS_JSON="{}"
TGT_USERNAME=""

# Database details
DB_TYPE=""
DB_SYSTEM_ID=""
DB_LISTENER_PORT=""
DB_SERVICE_NAME=""
DB_VM_CLUSTER_ID=""
DB_VM_CLUSTER_NAME=""
DB_SID_DERIVED=""
DB_VM_HOSTS=""
DB_CONNECTION_STRING=""

# --- Minimal bootstrap: ensure SCRIPT_BASE and libraries ----------------------
if [[ -z "${SCRIPT_BASE:-}" || -z "${SCRIPT_LIB_DIR:-}" ]]; then
    _SRC="${BASH_SOURCE[0]}"
    SCRIPT_BASE="$(cd "$(dirname "${_SRC}")/.." > /dev/null 2>&1 && pwd)"
    SCRIPT_LIB_DIR="${SCRIPT_BASE}/lib"
    unset _SRC
fi

# Load the odb_datasafe v0.2.0 framework
if [[ -r "${SCRIPT_LIB_DIR}/ds_lib.sh" ]]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_LIB_DIR}/ds_lib.sh" || {
        echo "ERROR: ds_lib.sh failed to load." >&2
        exit 1
    }
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
  ds_target_connect_details.sh -T <TARGET> [options]

Display connection details for an Oracle Data Safe target database including
listener port, service name, VM cluster hosts, and connection strings.

Mandatory:
  -T, --target <OCID|NAME>        Data Safe target (OCID or display name)

Optional:
  -c, --compartment <OCID|NAME>   Compartment scope for name resolution
  -O, --output-type table|json    Output format (default: ${OUTPUT_TYPE})

OCI CLI:
      --oci-config <file>         OCI CLI config file (default: ${OCI_CLI_CONFIG_FILE})
      --oci-profile <name>        OCI CLI profile     (default: ${OCI_CLI_PROFILE})

Logging / generic:
  -l, --log-file <file>           Write logs to <file>
  -v, --verbose                   Set log level to INFO
  -d, --debug                     Set log level to DEBUG
  -q, --quiet                     Suppress INFO/DEBUG/TRACE stdout
      --log-level <LEVEL>         ERROR|WARN|INFO|DEBUG|TRACE
  -h, --help                      Show this help and exit

Examples:
  # Show connection details for target by name
  ds_target_connect_details.sh -T exa118r05c15_cdb09a15_MYPDB

  # Show connection details for target by OCID (JSON output)
  ds_target_connect_details.sh -T ocid1.datasafetargetdatabase... -O json

  # Use explicit compartment for name resolution
  ds_target_connect_details.sh -T MYPDB -c my-compartment-name

EOF
    [[ "$exit_code" -ne 0 ]] && core_log_message ERROR "Wrong or missing mandatory parameters."
    core_exit_script "$exit_code"
}

# ------------------------------------------------------------------------------
# Function....: parse_common_opts
# Purpose.....: Parse standard CLI flags using the v0.2.0 framework pattern
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034  # VERBOSE, DEBUG, QUIET, EXPLICIT_LOG_LEVEL, REM_ARGS used by framework
parse_common_opts() {
    local -a args=("$@")
    local -a positional=()
    local i val

    for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[i]}" in
            -T | --target)
                core_need_val args "$i" TARGET
                ((++i))
                ;;
            -c | --compartment)
                core_need_val args "$i" COMPARTMENT
                ((++i))
                ;;
            -O | --output-type)
                core_need_val args "$i" val
                ((++i))
                case "$val" in
                    table | json) OUTPUT_TYPE="$val" ;;
                    *)
                        core_log_message ERROR "Invalid --output-type '$val' (use: table|json)"
                        Usage 2
                        ;;
                esac
                ;;
            --oci-config)
                core_need_val args "$i" OCI_CLI_CONFIG_FILE
                ((++i))
                ;;
            --oci-profile)
                core_need_val args "$i" OCI_CLI_PROFILE
                ((++i))
                ;;
            -l | --log-file)
                core_need_val args "$i" SCRIPT_LOG
                ((++i))
                ;;
            -v | --verbose) VERBOSE=true ;;
            -d | --debug) DEBUG=true ;;
            -q | --quiet) QUIET=true ;;
            --log-level)
                core_need_val args "$i" G_LOG_LEVEL
                ((++i))
                EXPLICIT_LOG_LEVEL=true
                ;;
            -h | --help) Usage 0 ;;
            --)
                ((++i))
                while ((i < ${#args[@]})); do positional+=("${args[i++]}"); done
                break
                ;;
            -*)
                core_log_message ERROR "Unknown option: ${args[i]}"
                Usage 2
                ;;
            *) positional+=("${args[i]}") ;;
        esac
    done

    REM_ARGS=()
    ((${#positional[@]})) && REM_ARGS=("${positional[@]}")

    set_log_level_from_flags || Usage 1
    update_log_level "$G_LOG_LEVEL" || Usage 1
}

# ------------------------------------------------------------------------------
# Function....: validate_inputs
# Purpose.....: Validate mandatory parameters and resolve compartment/target
# ------------------------------------------------------------------------------
validate_inputs() {
    # Check mandatory parameter
    [[ -z "${TARGET:-}" ]] && {
        core_log_message ERROR "Missing mandatory parameter: -T/--target"
        Usage 2
    }

    # Resolve compartment if provided
    if [[ -n "${COMPARTMENT:-}" ]]; then
        COMP_OCID="$(resolve_compartment_ocid "$COMPARTMENT")" || core_exit_script 22 "Failed to resolve OCID for compartment '${COMPARTMENT}'"
        COMP_NAME="$(resolve_compartment_name "$COMPARTMENT")" || COMP_NAME="$COMPARTMENT"
        core_log_message DEBUG "Selected compartment: ${COMP_NAME} (${COMP_OCID})"
    fi

    # Resolve Data Safe target
    TARGET_OCID="$(resolve_ds_target_ocid "$TARGET")" || core_exit_script 5 "Cannot resolve target OCID for '$TARGET'"
    TARGET_NAME="$(resolve_ds_target_name "$TARGET")" || core_exit_script 5 "Cannot resolve target name for '$TARGET'"
    core_log_message INFO "Processing target: ${TARGET_NAME} (${TARGET_OCID})"
}

# ------------------------------------------------------------------------------
# Function....: parse_display_name
# Purpose.....: Extract cluster, CDB, and PDB from display name
# Parameters..: $1 - display name (format: <cluster>_<cdb>_<pdb>)
# Returns.....: JSON object with cluster, cdb, pdb fields
# ------------------------------------------------------------------------------
parse_display_name() {
    local name="$1"
    echo "$name" | awk -F'_' '{printf("{\"cluster\":\"%s\",\"cdb\":\"%s\",\"pdb\":\"%s\"}\n", $1,$2,$3)}'
}

# ------------------------------------------------------------------------------
# Function....: fetch_target_details
# Purpose.....: Fetch and parse Data Safe target database details
# Globals.....: TARGET_OCID (read), TGT_* and DB_* variables (write)
# ------------------------------------------------------------------------------
fetch_target_details() {
    core_log_message DEBUG "Fetching target details for: ${TARGET_OCID}"

    local raw_json parsed
    raw_json="$(oci data-safe target-database get \
        --target-database-id "$TARGET_OCID" \
        --config-file "$OCI_CLI_CONFIG_FILE" \
        --profile "$OCI_CLI_PROFILE" 2>&1)" || {
        core_log_message ERROR "Failed to fetch target database details"
        return 1
    }

    # Parse JSON response
    parsed="$(echo "$raw_json" | jq -r '
    .data as $d |
    {
      id: ($d.id // ""),
      name: ($d["display-name"] // $d.displayName // ""),
      description: ($d.description // ""),
      status: ($d["lifecycle-state"] // $d.lifecycleState // ""),
      details: ($d["lifecycle-details"] // $d.lifecycleDetails // ""),
      compartment_id: ($d["compartment-id"] // $d.compartmentId // ""),
      conn_type: ($d["connection-option"]["connection-type"] // $d.connectionOption.connectionType // ""),
      onprem_ocid: ($d["connection-option"]["on-prem-connector-id"] // $d.connectionOption.onPremConnectorId // ""),
      freeform_tags: ($d["freeform-tags"] // $d.freeformTags // {}),
      user_name: ($d.credentials["user-name"] // $d.credentials.userName // ""),
      db_type: ($d["database-details"]["database-type"] // $d.databaseDetails.databaseType // ""),
      db_system_id: ($d["database-details"]["db-system-id"] // $d.databaseDetails.dbSystemId // ""),
      listener_port: ($d["database-details"]["listener-port"] // $d.databaseDetails.listenerPort // ""),
      service_name: ($d["database-details"]["service-name"] // $d.databaseDetails.serviceName // ""),
      vm_cluster_id: ($d["database-details"]["vm-cluster-id"] // $d.databaseDetails.vmClusterId // "")
    }
  ')" || {
        core_log_message ERROR "Failed to parse target database JSON"
        return 1
    }

    # Assign to globals
    TGT_ID="$(echo "$parsed" | jq -r '.id')"
    TGT_NAME="$(echo "$parsed" | jq -r '.name')"
    TGT_DESCRIPTION="$(echo "$parsed" | jq -r '.description')"
    TGT_STATUS="$(echo "$parsed" | jq -r '.status')"
    TGT_DETAILS="$(echo "$parsed" | jq -r '.details')"
    TGT_COMP_OCID="$(echo "$parsed" | jq -r '.compartment_id')"
    TGT_CONN_TYPE="$(echo "$parsed" | jq -r '.conn_type')"
    TGT_ONPREM_OCID="$(echo "$parsed" | jq -r '.onprem_ocid')"
    TGT_FREEFORM_TAGS_JSON="$(echo "$parsed" | jq -c '.freeform_tags | (if type=="object" then . else (try fromjson catch {}) end)')"
    TGT_USERNAME="$(echo "$parsed" | jq -r '.user_name')"

    DB_TYPE="$(echo "$parsed" | jq -r '.db_type')"
    DB_SYSTEM_ID="$(echo "$parsed" | jq -r '.db_system_id')"
    DB_LISTENER_PORT="$(echo "$parsed" | jq -r '.listener_port')"
    DB_SERVICE_NAME="$(echo "$parsed" | jq -r '.service_name')"
    DB_VM_CLUSTER_ID="$(echo "$parsed" | jq -r '.vm_cluster_id')"

    # Derive SID from display name
    if [[ -n "$TGT_NAME" ]]; then
        local derived cdb
        derived="$(parse_display_name "$TGT_NAME")"
        cdb="$(echo "$derived" | jq -r '.cdb')"
        DB_SID_DERIVED="$(echo "$cdb" | tr '[:lower:]' '[:upper:]')"
    fi

    core_log_message DEBUG "Parsed target: ${TGT_NAME} (${TGT_STATUS})"
    return 0
}

# ------------------------------------------------------------------------------
# Function....: resolve_additional_details
# Purpose.....: Resolve compartment name, on-prem connector, VM cluster, hosts
# ------------------------------------------------------------------------------
resolve_additional_details() {
    # Resolve compartment name
    if [[ -n "${TGT_COMP_OCID:-}" && "${TGT_COMP_OCID}" != "null" ]]; then
        TGT_COMP_NAME="$(resolve_compartment_name "${TGT_COMP_OCID}" 2> /dev/null || echo "")"
    fi

    # Resolve on-prem connector name
    if [[ -n "${TGT_ONPREM_OCID:-}" && "${TGT_ONPREM_OCID}" != "null" ]]; then
        TGT_ONPREM_NAME="$(resolve_onprem_connector_name "${TGT_ONPREM_OCID}" 2> /dev/null || echo "")"
    fi

    # Resolve VM cluster name
    if [[ -n "${DB_VM_CLUSTER_ID:-}" && "${DB_VM_CLUSTER_ID}" != "null" ]]; then
        DB_VM_CLUSTER_NAME="$(exacc_vmcluster_name_by_ocid "${DB_VM_CLUSTER_ID}" 2> /dev/null || echo "")"

        # Resolve cluster hosts
        if [[ -n "${DB_VM_CLUSTER_NAME:-}" && "${DB_VM_CLUSTER_NAME}" != "null" ]]; then
            DB_VM_HOSTS="$(resolve_cluster_hosts "$DB_VM_CLUSTER_NAME" 2> /dev/null || echo "")"
        fi
    fi

    # Build connection strings
    if [[ -n "${TGT_USERNAME:-}" && -n "${DB_VM_HOSTS:-}" && -n "${DB_LISTENER_PORT:-}" && -n "${DB_SERVICE_NAME:-}" ]]; then
        DB_CONNECTION_STRING=""
        while IFS= read -r host; do
            [[ -z "$host" ]] && continue
            local conn_str="sqlplus ${TGT_USERNAME}@${host}:${DB_LISTENER_PORT}/${DB_SERVICE_NAME}"
            if [[ -n "${DB_CONNECTION_STRING}" ]]; then
                DB_CONNECTION_STRING+=","
            fi
            DB_CONNECTION_STRING+="${conn_str}"
        done <<< "$(echo "$DB_VM_HOSTS" | tr ',' '\n')"
    fi
}

# ------------------------------------------------------------------------------
# Function....: output_table
# Purpose.....: Display connection details in table format
# ------------------------------------------------------------------------------
output_table() {
    local details_1l freeform_1l hosts_1l
    details_1l="$(echo "${TGT_DETAILS:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
    freeform_1l="$(echo "${TGT_FREEFORM_TAGS_JSON:-{}}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
    hosts_1l="$(echo "${DB_VM_HOSTS:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"

    printf '%-22s : %s\n' "Target Name" "${TGT_NAME:-}"
    printf '%-22s : %s\n' "Description" "${TGT_DESCRIPTION:-}"
    printf '%-22s : %s\n' "Status" "${TGT_STATUS:-}"
    printf '%-22s : %s\n' "Details" "$details_1l"
    printf '%-22s : %s\n' "Compartment" "${TGT_COMP_NAME:-} (${TGT_COMP_OCID:-})"
    printf '%-22s : %s\n' "Connection Type" "${TGT_CONN_TYPE:-}"
    printf '%-22s : %s\n' "On-Prem Connector" "${TGT_ONPREM_NAME:-} (${TGT_ONPREM_OCID:-})"
    printf '%-22s : %s\n' "Freeform Tags" "$freeform_1l"
    printf '%-22s : %s\n' "User Name" "${TGT_USERNAME:-}"
    printf '%-22s : %s\n' "Database Type" "${DB_TYPE:-}"
    printf '%-22s : %s\n' "Listener Port" "${DB_LISTENER_PORT:-}"
    printf '%-22s : %s\n' "Service Name" "${DB_SERVICE_NAME:-}"
    printf '%-22s : %s\n' "Oracle SID (derived)" "${DB_SID_DERIVED:-}"

    # Pretty-print Connection String across multiple lines
    local indent_width=22
    local label="Connection String"
    if [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
        IFS=',' read -r -a conn_array <<< "$DB_CONNECTION_STRING"
        for i in "${!conn_array[@]}"; do
            if ((i == 0)); then
                printf '%-*s : %s\n' "$indent_width" "$label" "${conn_array[i]}"
            else
                printf '%*s%s\n' "$((indent_width + 3))" "" "${conn_array[i]}"
            fi
        done
    else
        printf '%-*s : %s\n' "$indent_width" "$label" "(insufficient data)"
    fi

    printf '%-22s : %s\n' "VM Cluster" "${DB_VM_CLUSTER_NAME:-} (${DB_VM_CLUSTER_ID:-})"
    printf '%-22s : %s\n' "DB System ID" "${DB_SYSTEM_ID:-}"
    printf '%-22s : %s\n' "VM Cluster Hosts" "$hosts_1l"
}

# ------------------------------------------------------------------------------
# Function....: output_json
# Purpose.....: Display connection details in JSON format
# ------------------------------------------------------------------------------
output_json() {
    local hosts_nl="${DB_VM_HOSTS:-}"
    local conn_str="${DB_CONNECTION_STRING:-}"

    jq -n \
        --arg id "${TGT_ID:-}" \
        --arg name "${TGT_NAME:-}" \
        --arg description "${TGT_DESCRIPTION:-}" \
        --arg status "${TGT_STATUS:-}" \
        --arg details "${TGT_DETAILS:-}" \
        --arg compartment_id "${TGT_COMP_OCID:-}" \
        --arg compartment_name "${TGT_COMP_NAME:-}" \
        --arg conn_type "${TGT_CONN_TYPE:-}" \
        --arg onprem_id "${TGT_ONPREM_OCID:-}" \
        --arg onprem_name "${TGT_ONPREM_NAME:-}" \
        --arg user_name "${TGT_USERNAME:-}" \
        --arg db_type "${DB_TYPE:-}" \
        --arg listener_port "${DB_LISTENER_PORT:-}" \
        --arg service_name "${DB_SERVICE_NAME:-}" \
        --arg sid_derived "${DB_SID_DERIVED:-}" \
        --arg connect_string "$conn_str" \
        --arg vm_cluster_id "${DB_VM_CLUSTER_ID:-}" \
        --arg vm_cluster_name "${DB_VM_CLUSTER_NAME:-}" \
        --arg db_system_id "${DB_SYSTEM_ID:-}" \
        --arg hosts_nl "$hosts_nl" \
        --argjson freeform_tags "${TGT_FREEFORM_TAGS_JSON:-{}}" '
    def to_array($s):
      if ($s|length)==0 then []
      else ($s | split(",") | map(select(length>0)))
      end;

    {
      target: {
        id: $id,
        name: $name,
        description: $description,
        status: $status,
        details: $details,
        compartment: { id: $compartment_id, name: $compartment_name },
        connection: {
          type: $conn_type,
          onprem_connector: { id: $onprem_id, name: $onprem_name }
        },
        freeform_tags: $freeform_tags,
        credentials: { user_name: $user_name }
      },
      database: {
        type: $db_type,
        listener_port: (try ($listener_port|tonumber) catch null),
        service_name: $service_name,
        sid_derived: $sid_derived,
        connection_string: to_array($connect_string),
        vm_cluster: {
          id: $vm_cluster_id,
          name: $vm_cluster_name,
          hosts: to_array($hosts_nl)
        },
        db_system_id: (if $db_system_id=="" then null else $db_system_id end)
      }
    }'
}

# ------------------------------------------------------------------------------
# Function....: main
# Purpose.....: Main entry point
# ------------------------------------------------------------------------------
main() {
    init_config "$@" || core_exit_script 1 "init_config failed"
    parse_common_opts "$@" || core_exit_script 1 "parse_common_opts failed"
    validate_inputs || core_exit_script 1 "validate_inputs failed"

    fetch_target_details || core_exit_script 10 "Failed to fetch target details"
    resolve_additional_details || core_exit_script 10 "Failed to resolve additional details"

    case "${OUTPUT_TYPE:-table}" in
        json) output_json ;;
        *) output_table ;;
    esac

    core_exit_script 0 "Successfully retrieved connection details for ${TARGET_NAME}"
}

# --- Main script execution ----------------------------------------------------
main "$@"
# --- EOF ----------------------------------------------------------------------
