#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_update_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.05
# Version....: v0.19.1
# Purpose....: Update Oracle Data Safe target service names and/or listener ports
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.19.1')"
readonly SCRIPT_VERSION

# Defaults — Selection
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${TAG_FILTER:=}"
: "${LIFECYCLE_STATE:=ACTIVE}"
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${ALLOW_STALE_SELECTION:=false}"
: "${MAX_SNAPSHOT_AGE:=24h}"

# Defaults — Service/Port Update
: "${DB_DOMAIN:=oradba.ch}"
: "${LISTENER_PORT:=1521}"
: "${SERVICE_TEMPLATE:={pdb}_exa.{domain}}"
: "${ROOT_SERVICE_TEMPLATE:=}"
: "${UPDATE_SERVICE:=true}"
: "${UPDATE_PORT:=false}"
: "${FROM_OCI:=false}"
: "${PDB_COMPARTMENT:=}"

# Defaults — Execution
: "${APPLY_CHANGES:=false}"
: "${WAIT_STATE:=}"
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

# shellcheck disable=SC1091
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}

# Initialize configuration
init_config

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: usage
# Purpose.: Display script usage information
# Args....: None
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Update Oracle Data Safe target service names and/or listener ports.
  Service names are derived from the target display name using a configurable
  template (brace-style placeholders). Listener ports can be updated in the
  same API call. Root targets (CDB\$ROOT) require a separate template.

Options:
  Common:
    -h, --help                  Show this help message
    -V, --version               Show version
    -v, --verbose               Enable verbose output
    -d, --debug                 Enable debug output
        --log-file FILE         Log to file

  OCI:
        --oci-profile PROFILE   OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION     OCI region
        --oci-config FILE       OCI config file

  Selection:
    -c, --compartment ID        Compartment OCID or name (default: DS_ROOT_COMP)
                                Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                   Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST          Comma-separated target names or OCIDs
    -r, --filter REGEX          Filter target names by regex (substring match)
        --tag-filter EXPR       Filter by OCI tag (key=val, key, ns/key=val, ns/key); repeatable (AND)
    -L, --lifecycle STATE       Filter by lifecycle state (default: ${LIFECYCLE_STATE})
        --input-json FILE       Read targets from local JSON (array or {data:[...]})
        --save-json FILE        Save selected target JSON payload
        --allow-stale-selection Allow --apply with --input-json
                    (disabled by default for safety)
        --max-snapshot-age AGE  Max input-json age (default: ${MAX_SNAPSHOT_AGE})
                    Examples: 900, 30m, 24h, 2d, off

  Service Update:
        --domain DOMAIN         Domain for service name template (default: ${DB_DOMAIN})
        --service-template TMPL Template for non-root targets (default: ${SERVICE_TEMPLATE})
        --root-service-template TMPL
                                Template for CDB\$ROOT targets (default: skip with warning)
        --no-service-update     Skip service name update (port update only)
        --port PORT             Set listener port and enable port update
        --update-port           Enable port update using LISTENER_PORT from config (${LISTENER_PORT})
        --from-oci              Derive service name and port from OCI PDB connection string
                                (overrides --service-template; requires OCI access)
        --pdb-compartment COMP  Compartment for OCI PDB lookup (default: same as --compartment)
        --wait-state STATE      Wait for update to reach state (e.g. ACCEPTED)
        --apply                 Apply changes (default: dry-run only)
    -n, --dry-run               Dry-run mode (show what would be done)

Template Placeholders:
    {pdb}      PDB name, lowercase        {PDB}      PDB name, uppercase
    {cdb}      CDB name, lowercase        {CDB}      CDB name, uppercase
    {cluster}  Cluster name, lowercase    {CLUSTER}  Cluster name, uppercase
    {sid}      Oracle SID, lowercase      {SID}      Oracle SID, uppercase
               (alias for cdb — useful in root templates)
    {domain}   DB_DOMAIN value

  Display name is parsed as: <cluster>_<cdb>_<pdb> (or <cdb>_<pdb> if no cluster).
  Use DS_TARGET_NAME_REGEX in datasafe.conf to override parsing for complex names.

Template Examples:
    {pdb}_exa.{domain}           pdb01_exa.example.com  (default)
    {PDB}_PAAS.{domain}          PDB01_PAAS.example.com
    {pdb}_{cdb}.{domain}         pdb01_cdb01.example.com
    {cdb}.{domain}               cdb01.example.com          (root)
    {SID}_MGMT.{domain}          CDB01_MGMT.example.com     (root)

Examples:
    # Dry-run for all ACTIVE targets (default template)
    ${SCRIPT_NAME}

    # Apply with custom template
    ${SCRIPT_NAME} -c my-compartment --service-template "{PDB}_PAAS.{domain}" --apply

    # Update port only (no service change)
    ${SCRIPT_NAME} -c my-compartment --port 1565 --no-service-update --apply

    # Update service and port together
    ${SCRIPT_NAME} -c my-compartment --update-port --apply

    # Root and PDB templates
    ${SCRIPT_NAME} -c my-compartment \\
        --service-template "{pdb}_exa.{domain}" \\
        --root-service-template "{cdb}.{domain}" --apply

    # Derive service+port from OCI PDB connection string
    ${SCRIPT_NAME} -c my-compartment --from-oci --apply

    # From saved selection JSON (requires explicit safeguard override)
    ${SCRIPT_NAME} --input-json ./target_selection.json --apply --allow-stale-selection

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: parse_args
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global variables based on arguments
# ------------------------------------------------------------------------------
parse_args() {
    local has_explicit_log_flag="false"
    local arg
    for arg in "$@"; do
        case "$arg" in
            -v | --verbose | -d | --debug | -q | --quiet)
                has_explicit_log_flag="true"
                break
                ;;
        esac
    done

    parse_common_opts "$@"

    if [[ "$has_explicit_log_flag" == "false" ]]; then
        # shellcheck disable=SC2034
        LOG_LEVEL=INFO
    fi

    # Parse script-specific options
    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
                shift 2
                ;;
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -A | --all)
                SELECT_ALL=true
                shift
                ;;
            -r | --filter)
                need_val "$1" "${2:-}"
                TARGET_FILTER="$2"
                shift 2
                ;;
            --tag-filter)
                need_val "$1" "${2:-}"
                TAG_FILTER="${TAG_FILTER:+${TAG_FILTER}$'\n'}$2"
                shift 2
                ;;
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            --input-json)
                need_val "$1" "${2:-}"
                INPUT_JSON="$2"
                shift 2
                ;;
            --save-json)
                need_val "$1" "${2:-}"
                SAVE_JSON="$2"
                shift 2
                ;;
            --allow-stale-selection)
                ALLOW_STALE_SELECTION=true
                shift
                ;;
            --max-snapshot-age)
                need_val "$1" "${2:-}"
                MAX_SNAPSHOT_AGE="$2"
                shift 2
                ;;
            --domain)
                need_val "$1" "${2:-}"
                DB_DOMAIN="$2"
                shift 2
                ;;
            --service-template)
                need_val "$1" "${2:-}"
                SERVICE_TEMPLATE="$2"
                shift 2
                ;;
            --root-service-template)
                need_val "$1" "${2:-}"
                ROOT_SERVICE_TEMPLATE="$2"
                shift 2
                ;;
            --no-service-update)
                UPDATE_SERVICE=false
                shift
                ;;
            --port)
                need_val "$1" "${2:-}"
                LISTENER_PORT="$2"
                UPDATE_PORT=true
                shift 2
                ;;
            --update-port)
                UPDATE_PORT=true
                shift
                ;;
            --from-oci)
                FROM_OCI=true
                shift
                ;;
            --pdb-compartment)
                need_val "$1" "${2:-}"
                PDB_COMPARTMENT="$2"
                shift 2
                ;;
            --wait-state)
                need_val "$1" "${2:-}"
                WAIT_STATE="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                export OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                export OCI_CLI_CONFIG_FILE="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1 (use --help for usage)"
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # Handle positional arguments
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error via die()
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        ds_validate_input_json_freshness "$INPUT_JSON" "$MAX_SNAPSHOT_AGE" || die "Input JSON snapshot freshness check failed"

        if [[ "$APPLY_CHANGES" == "true" && "$ALLOW_STALE_SELECTION" != "true" ]]; then
            die "Refusing --apply with --input-json without --allow-stale-selection"
        fi

        if [[ "$SELECT_ALL" == "true" || -n "$COMPARTMENT" || -n "$TARGETS" ]]; then
            log_warn "Ignoring --all/--compartment/--targets when --input-json is provided"
        fi

        if [[ "$APPLY_CHANGES" == "true" || "$FROM_OCI" == "true" ]]; then
            require_oci_cli
        fi
    else
        require_oci_cli

        COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

        if [[ "$SELECT_ALL" == "true" ]]; then
            log_info "Using DS_ROOT_COMP scope via --all"
        fi

        # If no scope specified, use DS_ROOT_COMP as default when available
        if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
            if [[ -n "${DS_ROOT_COMP:-}" ]]; then
                COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to get root compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"
                log_info "No scope specified, using DS_ROOT_COMP: $COMPARTMENT"
            else
                usage
            fi
        fi
    fi

    # Resolve compartment if specified (accept name or OCID)
    if [[ -n "$COMPARTMENT" ]]; then
        if is_ocid "$COMPARTMENT"; then
            COMPARTMENT_OCID="$COMPARTMENT"
            COMPARTMENT_NAME=$(oci_get_compartment_name "$COMPARTMENT_OCID" 2> /dev/null) || COMPARTMENT_NAME="$COMPARTMENT_OCID"
            log_debug "Resolved compartment OCID to name: $COMPARTMENT_NAME"
        else
            COMPARTMENT_NAME="$COMPARTMENT"
            COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || {
                die "Cannot resolve compartment name '$COMPARTMENT' to OCID.\nVerify compartment name or use OCID directly."
            }
            log_debug "Resolved compartment name to OCID: $COMPARTMENT_OCID"
        fi
        log_info "Using compartment: $COMPARTMENT_NAME"
    fi

    # Validate update flags
    if [[ "$UPDATE_SERVICE" == "false" && "$UPDATE_PORT" == "false" && "$FROM_OCI" == "false" ]]; then
        die "Nothing to update. Specify --service-template/--domain for service, --port/--update-port for port, or --from-oci."
    fi

    # Validate listener port when updating
    if [[ "$UPDATE_PORT" == "true" ]]; then
        [[ "$LISTENER_PORT" =~ ^[0-9]+$ && "$LISTENER_PORT" -ge 1 && "$LISTENER_PORT" -le 65535 ]] ||
            die "Invalid listener port: $LISTENER_PORT (must be 1-65535)"
        log_info "Listener port update enabled: $LISTENER_PORT"
    fi

    # Validate domain
    [[ -n "$DB_DOMAIN" ]] || die "Domain cannot be empty (use --domain)"

    # Resolve PDB compartment for --from-oci
    if [[ "$FROM_OCI" == "true" ]]; then
        log_info "--from-oci enabled: will query OCI for PDB connection strings"
        if [[ -n "$PDB_COMPARTMENT" ]]; then
            if is_ocid "$PDB_COMPARTMENT"; then
                PDB_COMPARTMENT_OCID="$PDB_COMPARTMENT"
            else
                PDB_COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$PDB_COMPARTMENT") ||
                    die "Cannot resolve --pdb-compartment: $PDB_COMPARTMENT"
            fi
            log_info "PDB lookup compartment: $PDB_COMPARTMENT ($PDB_COMPARTMENT_OCID)"
        elif [[ -n "${COMPARTMENT_OCID:-}" ]]; then
            PDB_COMPARTMENT_OCID="$COMPARTMENT_OCID"
            log_info "PDB lookup compartment: same as targets ($COMPARTMENT_OCID)"
        else
            die "--from-oci requires --compartment or --pdb-compartment for PDB lookup"
        fi
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: parse_target_display_name
# Purpose.: Parse target display name into cluster/cdb/pdb components
# Args....: $1 - Display name (e.g. CLUSTER_CDB01_PDB01 or CDB01_PDB01)
# Returns.: 0 on success
# Output..: "cluster|cdb|pdb" to stdout
# Notes...: Uses DS_TARGET_NAME_REGEX if configured in datasafe.conf
# ------------------------------------------------------------------------------
parse_target_display_name() {
    local name="$1"
    local cluster="" cdb="" pdb=""

    if [[ -n "${DS_TARGET_NAME_REGEX:-}" ]] && [[ "$name" =~ ${DS_TARGET_NAME_REGEX} ]]; then
        cluster="${BASH_REMATCH[1]}"
        cdb="${BASH_REMATCH[2]}"
        pdb="${BASH_REMATCH[3]}"
    else
        local sep="${DS_TARGET_NAME_SEPARATOR:-_}"
        IFS="$sep" read -r cluster cdb pdb <<< "$name"
        # Two-part name: treat as cdb_pdb (no cluster)
        if [[ -z "$pdb" ]]; then
            pdb="$cdb"
            cdb="$cluster"
            cluster=""
        fi
    fi

    printf '%s|%s|%s' "$cluster" "$cdb" "$pdb"
}

# ------------------------------------------------------------------------------
# Function: apply_service_template
# Purpose.: Expand a service name template using display-name components
# Args....: $1 - Target display name
#           $2 - Template string (e.g. "{pdb}_exa.{domain}")
#           $3 - Domain (DB_DOMAIN)
# Returns.: 0 on success
# Output..: Expanded service name to stdout
# Placeholders:
#   {pdb}/{PDB}       PDB name lower/upper
#   {cdb}/{CDB}       CDB name lower/upper
#   {cluster}/{CLUSTER} Cluster name lower/upper
#   {sid}/{SID}       Oracle SID lower/upper (alias for cdb)
#   {domain}          DB_DOMAIN value
# ------------------------------------------------------------------------------
apply_service_template() {
    local display_name="$1"
    local template="$2"
    local domain="$3"

    local parsed cluster cdb pdb
    parsed=$(parse_target_display_name "$display_name")
    IFS='|' read -r cluster cdb pdb <<< "$parsed"

    local result="$template"
    result="${result//\{pdb\}/${pdb,,}}"
    result="${result//\{PDB\}/${pdb^^}}"
    result="${result//\{cdb\}/${cdb,,}}"
    result="${result//\{CDB\}/${cdb^^}}"
    result="${result//\{cluster\}/${cluster,,}}"
    result="${result//\{CLUSTER\}/${cluster^^}}"
    result="${result//\{domain\}/$domain}"
    result="${result//\{sid\}/${cdb,,}}"
    result="${result//\{SID\}/${cdb^^}}"

    printf '%s' "$result"
}

# ------------------------------------------------------------------------------
# Function: update_target_service
# Purpose.: Compute and apply service name / listener port update for one target
# Args....: $1 - Target OCID
#           $2 - Target display name
#           $3 - Current service name (may be empty)
#           $4 - Current listener port (may be 0 or empty)
# Returns.: 0 on success (including no-change), 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
update_target_service() {
    local target_ocid="$1"
    local display_name="$2"
    local current_service="${3:-}"
    local current_port="${4:-0}"

    log_debug "Processing target: $display_name ($target_ocid)"
    log_debug "  Current service: '${current_service}', port: $current_port"

    # Parse display name → cluster|cdb|pdb
    local parsed cluster cdb pdb
    parsed=$(parse_target_display_name "$display_name")
    IFS='|' read -r cluster cdb pdb <<< "$parsed"
    log_debug "  Parsed: cluster='$cluster' cdb='$cdb' pdb='$pdb'"

    # Detect root target
    local cdbroot_regex="${DS_TARGET_NAME_CDBROOT_REGEX:-^(CDB\$ROOT|CDBROOT)$}"
    local is_root=false
    if [[ "$pdb" =~ $cdbroot_regex ]]; then
        is_root=true
        log_debug "  Detected as CDB\$ROOT target"
    fi

    # Determine values to apply
    local new_service="$current_service"
    local new_port="$current_port"
    local service_changed=false
    local port_changed=false

    # --- Service name ---
    if [[ "$FROM_OCI" == "true" ]]; then
        # Query OCI PDB for connection string
        local oci_result
        if oci_result=$(oci_lookup_pdb_connection "$pdb" "$PDB_COMPARTMENT_OCID"); then
            local oci_service oci_port
            IFS='|' read -r oci_service oci_port <<< "$oci_result"
            log_info "  OCI PDB connection: service='$oci_service' port='$oci_port'"
            if [[ "$UPDATE_SERVICE" != "false" ]]; then
                new_service="$oci_service"
            fi
            # --from-oci implicitly provides the port
            new_port="$oci_port"
        else
            log_warn "  OCI PDB lookup failed for '$pdb' — skipping target"
            return 0
        fi
    elif [[ "$UPDATE_SERVICE" == "true" ]]; then
        if [[ "$is_root" == "true" ]]; then
            if [[ -z "$ROOT_SERVICE_TEMPLATE" ]]; then
                log_warn "  Skipping root target '$display_name' (no --root-service-template configured)"
                return 0
            fi
            new_service=$(apply_service_template "$display_name" "$ROOT_SERVICE_TEMPLATE" "$DB_DOMAIN")
        else
            new_service=$(apply_service_template "$display_name" "$SERVICE_TEMPLATE" "$DB_DOMAIN")
        fi
    fi

    # --- Listener port (when not set by --from-oci above) ---
    if [[ "$UPDATE_PORT" == "true" && "$FROM_OCI" == "false" ]]; then
        new_port="$LISTENER_PORT"
    fi

    # Detect what changed
    [[ "$UPDATE_SERVICE" != "false" && "$new_service" != "$current_service" ]] && service_changed=true
    [[ ( "$UPDATE_PORT" == "true" || "$FROM_OCI" == "true" ) && "$new_port" != "$current_port" ]] && port_changed=true

    # Log planned action
    log_info "Target: $display_name"
    if [[ "$UPDATE_SERVICE" != "false" ]]; then
        log_info "  Service: '$current_service' → '$new_service'$([ "$service_changed" = "true" ] || echo ' (no change)')"
    fi
    if [[ "$UPDATE_PORT" == "true" || "$FROM_OCI" == "true" ]]; then
        log_info "  Port:    $current_port → $new_port$([ "$port_changed" = "true" ] || echo ' (no change)')"
    fi

    # Nothing changed
    if [[ "$service_changed" == "false" && "$port_changed" == "false" ]]; then
        log_info "  [OK] No change needed"
        return 0
    fi

    # Build --database-details JSON with only the fields being updated
    local db_details="{}"
    if [[ "$service_changed" == "true" ]]; then
        db_details=$(printf '%s' "$db_details" | jq --arg v "$new_service" '. + {serviceName: $v}')
    fi
    if [[ "$port_changed" == "true" ]]; then
        db_details=$(printf '%s' "$db_details" | jq --argjson v "$new_port" '. + {listenerPort: $v}')
    fi
    log_debug "  database-details JSON: $db_details"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "  Updating..."

        local -a cmd=(
            data-safe target-database update
            --target-database-id "$target_ocid"
            --connection-option '{"connectionType": "PRIVATE_ENDPOINT", "datasafePrivateEndpointId": null}'
            --database-details "$db_details"
        )

        if [[ -n "$WAIT_STATE" ]]; then
            cmd+=(--wait-for-state "$WAIT_STATE")
        fi

        if oci_exec "${cmd[@]}" > /dev/null; then
            log_info "  [OK] Updated successfully"
            return 0
        else
            log_error "  [ERROR] Failed to update target"
            return 1
        fi
    else
        log_info "  (Dry-run — use --apply to apply)"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Function: get_target_details
# Purpose.: Get target details including service name and listener port
# Args....: $1 - Target OCID
# Returns.: 0 on success, 1 on error
# Output..: JSON object with target details to stdout
# ------------------------------------------------------------------------------
get_target_details() {
    local target_ocid="$1"
    log_debug "Getting details for: $target_ocid"
    oci_exec_ro data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - processes targets and updates service/port
# Args....: None
# Returns.: 0 on success, 1 if any errors occurred
# Output..: Progress messages and summary statistics
# ------------------------------------------------------------------------------
do_work() {
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log_info "Apply mode: Changes will be applied"
    else
        log_info "Dry-run mode: No changes will be applied (use --apply to apply)"
    fi

    local success_count=0 error_count=0
    local -a target_rows=()

    log_info "Discovering targets (lifecycle: $LIFECYCLE_STATE)"

    local json_data
    json_data=$(ds_collect_targets_source "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER" "$INPUT_JSON" "$SAVE_JSON" "$TAG_FILTER") || die "Failed to collect targets"

    mapfile -t target_rows < <(echo "$json_data" | jq -r '.data[] |
        [
            (.id // ""),
            (."display-name" // ""),
            (.databaseDetails.serviceName // ."database-details"."service-name" // ""),
            ((."database-details"."listener-port" // .databaseDetails.listenerPort // 0) | tostring)
        ] | @tsv')

    local total_count=${#target_rows[@]}
    log_info "Found $total_count targets to process"

    if [[ $total_count -eq 0 ]]; then
        if [[ -n "$TARGET_FILTER" ]]; then
            die "No targets matched filter regex: $TARGET_FILTER" 1
        fi
        log_warn "No targets found"
        return 0
    fi

    local current=0
    local target_row target_ocid target_name current_service current_port target_data

    for target_row in "${target_rows[@]}"; do
        IFS=$'\t' read -r target_ocid target_name current_service current_port <<< "$target_row"
        [[ -z "$target_ocid" ]] && continue
        current=$((current + 1))

        # Fetch details when service name is missing and not using input-json
        if [[ -z "$current_service" && -z "$INPUT_JSON" ]]; then
            if ! target_data=$(get_target_details "$target_ocid"); then
                log_error "[$current/$total_count] Failed to get details for: $target_ocid"
                error_count=$((error_count + 1))
                continue
            fi
            target_name=$(printf '%s' "$target_data" | jq -r '."display-name"')
            current_service=$(printf '%s' "$target_data" | jq -r '.databaseDetails.serviceName // ."database-details"."service-name" // ""')
            current_port=$(printf '%s' "$target_data" | jq -r '(."database-details"."listener-port" // .databaseDetails.listenerPort // 0) | tostring')
        fi

        log_info "[$current/$total_count] Processing: $target_name"
        if update_target_service "$target_ocid" "$target_name" "$current_service" "$current_port"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done

    log_info "Update completed: successful=$success_count errors=$error_count"
    [[ $error_count -gt 0 ]] && return 1 || return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Validate inputs
    validate_inputs

    # Execute main work
    if do_work; then
        log_info "Service update completed successfully"
    else
        die "Service update failed with errors"
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
fi

parse_args "$@"
main

# --- End of ds_target_update_service.sh ---------------------------------------
