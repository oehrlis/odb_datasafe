#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_list.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.20
# Version....: v0.16.1
# Purpose....: List Oracle Data Safe target databases with summary or details
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.7.1')"
readonly SCRIPT_VERSION
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE_STATE:=}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${OUTPUT_GROUP:=default}" # default|overview|troubleshooting
: "${SHOW_COUNT:=false}"    # Default to list mode
: "${FIELDS:=display-name,lifecycle-state,infrastructure-type}"
: "${SHOW_PROBLEMS:=false}"
: "${GROUP_PROBLEMS:=false}"
: "${SHOW_DETAILS:=true}"
: "${SHOW_OVERVIEW:=false}"
: "${OVERVIEW_INCLUDE_STATUS:=true}"
: "${OVERVIEW_INCLUDE_MEMBERS:=true}"
: "${OVERVIEW_TRUNCATE_MEMBERS:=true}"
: "${OVERVIEW_MEMBERS_MAX_WIDTH:=80}"
: "${SHOW_HEALTH_OVERVIEW:=false}"
: "${SHOW_HEALTH_DETAILS:=false}"
: "${SHOW_HEALTH_ACTIONS:=true}"
: "${HEALTH_NORMAL_STATES:=ACTIVE,UPDATING}"
: "${DS_TARGET_NAME_REGEX:=}"
: "${DS_TARGET_NAME_SEPARATOR:=_}"
: "${DS_TARGET_NAME_ROOT_LABEL:=CDB\$ROOT}"
: "${DS_TARGET_NAME_CDBROOT_REGEX:=^(CDB\\\$ROOT|CDBROOT)$}"
: "${DS_TARGET_NAME_SID_REGEX:=^cdb[0-9]+[[:alnum:]]*$}"

# Runtime counters
: "${OVERVIEW_PARSE_SKIPPED:=0}"

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
  List Oracle Data Safe target databases. Display summary counts or detailed
  information based on compartment and lifecycle state filters.

Options:
  Common:
    -h, --help                          Show this help message
    -V, --version                       Show version
    -v, --verbose                       Enable verbose output
    -d, --debug                         Enable debug output
    -q, --quiet                         Suppress INFO messages (warnings/errors only)
    -n, --dry-run                       Dry-run mode (show what would be done)
    --log-file FILE                     Log to file

  OCI:
    --oci-profile PROFILE               OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
    --oci-region REGION                 OCI region
    --oci-config FILE                   OCI config file (default: ${OCI_CLI_CONFIG_FILE:-~/.oci/config})

  Selection:
    -c, --compartment ID                Compartment OCID or name (default: DS_ROOT_COMP)
                                        Configure in: \$ODB_DATASAFE_BASE/.env or datasafe.conf
    -A, --all                           Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -T, --targets LIST                  Comma-separated target names or OCIDs (for details only)
    -r, --filter REGEX                  Filter target names by regex (substring match)
    -L, --lifecycle STATE               Filter by lifecycle state (ACTIVE, NEEDS_ATTENTION, etc.)

  Output:
    Mode selection (choose one primary mode):
    -D, --details                       Show detailed target information (default)
    -C, --count                         Show summary count by lifecycle state
        --overview                      Show overview grouped by cluster and SID
        --health-overview               Show troubleshooting health overview
        --problems                      Show NEEDS_ATTENTION targets with lifecycle details
        --group-problems                Group NEEDS_ATTENTION targets by problem type

    Group selector (alternative to direct mode flags):
    -G, --output-group GROUP            default|overview|troubleshooting
                                        default: standard details/count behavior
                                        overview: same as --overview
                                        troubleshooting: health/problem group
                                        (defaults to --health-overview)

    Overview options (only with --overview or -G overview):
        --overview-status               Include lifecycle counts per SID row (default)
        --overview-no-status            Hide lifecycle counts in overview output
        --overview-no-members           Hide member/PDB names in overview output
        --overview-truncate-members     Truncate member/PDB list in table output (default)
        --overview-no-truncate-members  Show full member/PDB list in table output

    Troubleshooting options:
        --health-details                Include issue drill-down details (with --health-overview)
        --health-actions                Include suggested actions in health output (default)
        --health-no-actions             Hide suggested actions in health output
        --summary                       Summary only for --group-problems (no target list)

    Format and fields:
    -f, --format FMT                    Output format: table|json|csv (default: table)
    -F, --fields FIELDS                 Comma-separated fields for details (default: ${FIELDS})

    Overview Parsing:
        Target names are parsed as: <cluster>_<oracle_sid>_<cdb/pdb>
        Default parsing splits from right using separator "${DS_TARGET_NAME_SEPARATOR}".
        Optional regex override via config: DS_TARGET_NAME_REGEX with 3 capture groups
        for cluster, sid, and cdb/pdb respectively.
        SID token detection for default parser can be tuned with
        DS_TARGET_NAME_SID_REGEX (used to preserve db names with underscores).

Examples:
    # Default detailed list for DS_ROOT_COMP
    ${SCRIPT_NAME}

    # Show count summary
    ${SCRIPT_NAME} -C

    # Grouped mode selector: overview
    ${SCRIPT_NAME} -G overview

    # Grouped mode selector: troubleshooting (defaults to health overview)
    ${SCRIPT_NAME} -G troubleshooting

    # Direct overview mode with concise output
    ${SCRIPT_NAME} --overview --overview-no-members

    # Health troubleshooting with drill-down details
    ${SCRIPT_NAME} --health-overview --health-details

    # Problems grouped summary
    ${SCRIPT_NAME} --group-problems --summary

    # JSON output for automation
    ${SCRIPT_NAME} -f json

    # More examples and operational recipes:
    See doc/quickref.md

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
    parse_common_opts "$@"

    # Reset defaults (override any env/config values)
    # These can be explicitly set via command-line options
    [[ -z "${OUTPUT_FORMAT_OVERRIDE:-}" ]] && OUTPUT_FORMAT="table"
    [[ -z "${SHOW_COUNT_OVERRIDE:-}" ]] && SHOW_COUNT="false"
    [[ -z "${FIELDS_OVERRIDE:-}" ]] && FIELDS="display-name,lifecycle-state,infrastructure-type"

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
            -L | --lifecycle)
                need_val "$1" "${2:-}"
                LIFECYCLE_STATE="$2"
                shift 2
                ;;
            -C | --count)
                SHOW_COUNT=true
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            -G | --output-group)
                need_val "$1" "${2:-}"
                OUTPUT_GROUP="$2"
                shift 2
                ;;
            -D | --details)
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --overview)
                SHOW_OVERVIEW=true
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --overview-status)
                OVERVIEW_INCLUDE_STATUS=true
                shift
                ;;
            --overview-no-status)
                OVERVIEW_INCLUDE_STATUS=false
                shift
                ;;
            --overview-no-members)
                OVERVIEW_INCLUDE_MEMBERS=false
                shift
                ;;
            --overview-truncate-members)
                OVERVIEW_TRUNCATE_MEMBERS=true
                shift
                ;;
            --overview-no-truncate-members)
                OVERVIEW_TRUNCATE_MEMBERS=false
                shift
                ;;
            --health-overview)
                SHOW_HEALTH_OVERVIEW=true
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --health-details)
                SHOW_HEALTH_DETAILS=true
                SHOW_HEALTH_OVERVIEW=true
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --health-actions)
                SHOW_HEALTH_ACTIONS=true
                shift
                ;;
            --health-no-actions)
                SHOW_HEALTH_ACTIONS=false
                shift
                ;;
            -f | --format)
                need_val "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                OUTPUT_FORMAT_OVERRIDE=true
                shift 2
                ;;
            -F | --fields)
                need_val "$1" "${2:-}"
                FIELDS="$2"
                FIELDS_OVERRIDE=true
                shift 2
                ;;
            --problems)
                SHOW_PROBLEMS=true
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --group-problems)
                GROUP_PROBLEMS=true
                SHOW_PROBLEMS=true
                SHOW_COUNT=false
                SHOW_COUNT_OVERRIDE=true
                shift
                ;;
            --summary)
                SHOW_DETAILS=false
                shift
                ;;
            --oci-profile)
                need_val "$1" "${2:-}"
                OCI_CLI_PROFILE="$2"
                shift 2
                ;;
            --oci-region)
                need_val "$1" "${2:-}"
                export OCI_CLI_REGION="$2"
                shift 2
                ;;
            --oci-config)
                need_val "$1" "${2:-}"
                OCI_CLI_CONFIG_FILE="$2"
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

    # Handle positional arguments (treat as targets)
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
            TARGETS="${TARGETS// /,}"
        else
            log_warn "Ignoring positional args, targets already specified: ${remaining[*]}"
        fi
    fi

    # Validate output format
    case "${OUTPUT_FORMAT}" in
        table | json | csv) : ;;
        *) die "Invalid output format: '${OUTPUT_FORMAT}'. Use table, json, or csv" ;;
    esac

    # Validate output group
    case "${OUTPUT_GROUP}" in
        default | overview | troubleshooting) : ;;
        *) die "Invalid output group: '${OUTPUT_GROUP}'. Use default, overview, or troubleshooting" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: validate_inputs
# Purpose.: Validate command-line arguments and required conditions
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages for validation steps
# ------------------------------------------------------------------------------
validate_inputs() {
    log_debug "Validating inputs..."

    require_oci_cli

    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    if [[ "$SELECT_ALL" == "true" ]]; then
        log_info "Using DS_ROOT_COMP scope via --all"
    fi

    # Resolve compartment using new pattern: explicit -c > DS_ROOT_COMP > error
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"

        # Get compartment name for display
        local comp_name
        comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="<unknown>"

        log_debug "Using root compartment OCID: $COMPARTMENT"
        log_info "Using root compartment: $comp_name (includes sub-compartments)"
    fi

    # Count mode doesn't work with specific targets
    if [[ "$SHOW_COUNT" == "true" && -n "$TARGETS" ]]; then
        die "Count mode (-C) cannot be used with specific targets (-T). Use --details instead."
    fi

    # Apply grouped output behavior
    case "${OUTPUT_GROUP}" in
        overview)
            if [[ "$SHOW_HEALTH_OVERVIEW" == "true" || "$SHOW_PROBLEMS" == "true" || "$GROUP_PROBLEMS" == "true" || "$SHOW_COUNT" == "true" ]]; then
                die "--output-group overview cannot be combined with health/problem/count modes"
            fi
            SHOW_OVERVIEW=true
            SHOW_COUNT=false
            ;;
        troubleshooting)
            if [[ "$SHOW_OVERVIEW" == "true" || "$SHOW_COUNT" == "true" ]]; then
                die "--output-group troubleshooting cannot be combined with --overview or --count"
            fi
            if [[ "$SHOW_HEALTH_OVERVIEW" != "true" && "$SHOW_PROBLEMS" != "true" && "$GROUP_PROBLEMS" != "true" ]]; then
                SHOW_HEALTH_OVERVIEW=true
            fi
            SHOW_COUNT=false
            ;;
        default)
            :
            ;;
    esac

    # Problems mode does not support explicit targets
    if [[ "$SHOW_PROBLEMS" == "true" && -n "$TARGETS" ]]; then
        die "Problems mode (--problems) cannot be used with specific targets (-T)."
    fi

    # Normalize fields
    local fields_lower
    fields_lower=$(echo "$FIELDS" | tr '[:upper:]' '[:lower:]')
    if [[ "$fields_lower" == "all" ]]; then
        FIELDS="all"
        if [[ "$OUTPUT_FORMAT" != "json" ]]; then
            die "-F all is only supported with --format json"
        fi
    fi

    if [[ "$SHOW_PROBLEMS" == "true" ]]; then
        LIFECYCLE_STATE="NEEDS_ATTENTION"
        FIELDS="display-name,lifecycle-details"
    fi

    if [[ "$SHOW_OVERVIEW" == "true" ]]; then
        if [[ "$SHOW_PROBLEMS" == "true" || "$GROUP_PROBLEMS" == "true" ]]; then
            die "Overview mode (--overview) cannot be combined with --problems/--group-problems"
        fi

        if [[ "$SHOW_COUNT" == "true" ]]; then
            die "Overview mode (--overview) cannot be combined with --count"
        fi

        if [[ -n "${FIELDS_OVERRIDE:-}" ]]; then
            log_warn "Ignoring --fields in overview mode"
        fi
    fi

    if [[ "$SHOW_HEALTH_OVERVIEW" == "true" ]]; then
        if [[ "$SHOW_OVERVIEW" == "true" || "$SHOW_PROBLEMS" == "true" || "$GROUP_PROBLEMS" == "true" || "$SHOW_COUNT" == "true" ]]; then
            die "Health overview mode cannot be combined with --overview, --problems, --group-problems, or --count"
        fi

        if [[ -n "${FIELDS_OVERRIDE:-}" ]]; then
            log_warn "Ignoring --fields in health overview mode"
        fi
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: join_by
# Purpose.: Join an array of values with separator
# Args....: $1 - separator
#           $@ - values
# Returns.: 0
# Output..: Joined values to stdout
# ------------------------------------------------------------------------------
join_by() {
    local separator="$1"
    shift

    if [[ $# -eq 0 ]]; then
        echo ""
        return 0
    fi

    local result="$1"
    shift
    for value in "$@"; do
        result+="${separator}${value}"
    done
    echo "$result"
}

# ------------------------------------------------------------------------------
# Function: short_status_code
# Purpose.: Map lifecycle-state value to short code
# Args....: $1 - lifecycle state
# Returns.: 0
# Output..: short code to stdout
# ------------------------------------------------------------------------------
short_status_code() {
    local lifecycle_state="$1"

    case "$lifecycle_state" in
        ACTIVE)
            echo "A"
            ;;
        NEEDS_ATTENTION)
            echo "N"
            ;;
        INACTIVE)
            echo "I"
            ;;
        UPDATING)
            echo "U"
            ;;
        REGISTERING)
            echo "R"
            ;;
        DELETING)
            echo "D"
            ;;
        *)
            echo "${lifecycle_state:0:1}"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: is_cdbroot_name
# Purpose.: Check if database token represents CDB root
# Args....: $1 - cdb/pdb token
# Returns.: 0 if CDB root, 1 otherwise
# ------------------------------------------------------------------------------
is_cdbroot_name() {
    local db_name="$1"
    [[ "$db_name" =~ $DS_TARGET_NAME_CDBROOT_REGEX ]]
}

# ------------------------------------------------------------------------------
# Function: parse_target_name_components
# Purpose.: Parse target display name into cluster, SID, and cdb/pdb token
# Args....: $1 - target display name
# Returns.: 0 on success, 1 on parse failure
# Output..: tab-separated cluster, sid, db token
# ------------------------------------------------------------------------------
parse_target_name_components() {
    local display_name="$1"

    if [[ -n "$DS_TARGET_NAME_REGEX" ]]; then
        if [[ "$display_name" =~ $DS_TARGET_NAME_REGEX ]]; then
            printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
            return 0
        fi
        return 1
    fi

    local separator="$DS_TARGET_NAME_SEPARATOR"
    local remainder="$display_name"
    local -a parts=()

    while [[ "$remainder" == *"$separator"* ]]; do
        parts+=("${remainder%%"$separator"*}")
        remainder="${remainder#*"$separator"}"
    done
    parts+=("$remainder")

    local part_count=${#parts[@]}
    if ((part_count < 3)); then
        return 1
    fi

    local sid_idx=-1
    local idx
    for ((idx = part_count - 2; idx >= 1; idx--)); do
        if [[ "${parts[$idx]}" =~ $DS_TARGET_NAME_SID_REGEX ]]; then
            sid_idx=$idx
            break
        fi
    done

    local sid db_token
    local -a cluster_parts=() db_parts=()

    if ((sid_idx >= 1)); then
        sid="${parts[$sid_idx]}"

        for ((idx = 0; idx < sid_idx; idx++)); do
            cluster_parts+=("${parts[$idx]}")
        done

        for ((idx = sid_idx + 1; idx < part_count; idx++)); do
            db_parts+=("${parts[$idx]}")
        done

        if [[ ${#cluster_parts[@]} -eq 0 || ${#db_parts[@]} -eq 0 ]]; then
            return 1
        fi

        db_token=$(join_by "$separator" "${db_parts[@]}")
    else
        db_token="${parts[$((part_count - 1))]}"
        sid="${parts[$((part_count - 2))]}"
        for ((idx = 0; idx < part_count - 2; idx++)); do
            cluster_parts+=("${parts[$idx]}")
        done
    fi

    local cluster
    cluster=$(join_by "$separator" "${cluster_parts[@]}")

    printf '%s\t%s\t%s\n' "$cluster" "$sid" "$db_token"
}

# ------------------------------------------------------------------------------
# Function: build_overview_rows
# Purpose.: Aggregate selected targets by cluster and SID
# Args....: $1 - JSON data object with .data array
# Returns.: 0 on success
# Output..: tab-separated rows with overview columns
# ------------------------------------------------------------------------------
build_overview_rows() {
    local json_data="$1"
    OVERVIEW_PARSE_SKIPPED=0

    local -A grouped_keys=()
    local -A total_counts=()
    local -A cdb_counts=()
    local -A pdb_counts=()
    local -A member_lists=()
    local -A member_seen=()
    local -A state_counts=()

    while IFS=$'\t' read -r display_name lifecycle_state; do
        [[ -z "$display_name" ]] && continue

        local parsed
        if ! parsed=$(parse_target_name_components "$display_name"); then
            OVERVIEW_PARSE_SKIPPED=$((OVERVIEW_PARSE_SKIPPED + 1))
            continue
        fi

        local cluster sid db_token
        IFS=$'\t' read -r cluster sid db_token <<< "$parsed"
        local key="${cluster}|${sid}"
        grouped_keys["$key"]=1

        total_counts["$key"]=$((${total_counts["$key"]:-0} + 1))

        local member_name="$db_token"
        if is_cdbroot_name "$db_token"; then
            cdb_counts["$key"]=$((${cdb_counts["$key"]:-0} + 1))
            member_name="$DS_TARGET_NAME_ROOT_LABEL"
        else
            pdb_counts["$key"]=$((${pdb_counts["$key"]:-0} + 1))
        fi

        local member_key="${key}|${member_name}"
        if [[ -z "${member_seen["$member_key"]:-}" ]]; then
            if [[ -n "${member_lists["$key"]:-}" ]]; then
                member_lists["$key"]+=","
            fi
            member_lists["$key"]+="$member_name"
            member_seen["$member_key"]=1
        fi

        local state="${lifecycle_state:-UNKNOWN}"
        local state_key="${key}|${state}"
        state_counts["$state_key"]=$((${state_counts["$state_key"]:-0} + 1))
    done < <(echo "$json_data" | jq -r '.data[] | [."display-name" // "", ."lifecycle-state" // "UNKNOWN"] | @tsv')

    local key
    for key in "${!grouped_keys[@]}"; do
        local cluster sid
        IFS='|' read -r cluster sid <<< "$key"

        local status_summary=""
        if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
            local -a status_parts=()
            local state_key state count
            for state_key in "${!state_counts[@]}"; do
                if [[ "$state_key" == "${key}|"* ]]; then
                    state="${state_key#${key}|}"
                    count="${state_counts["$state_key"]}"
                    status_parts+=("$(short_status_code "$state")=${count}")
                fi
            done

            if [[ ${#status_parts[@]} -gt 0 ]]; then
                status_summary=$(printf '%s\n' "${status_parts[@]}" | sort | paste -sd',' -)
            fi
        fi

        printf '%s\t%s\t%d\t%d\t%d\t%s\t%s\n' \
            "$cluster" \
            "$sid" \
            "${cdb_counts["$key"]:-0}" \
            "${pdb_counts["$key"]:-0}" \
            "${total_counts["$key"]:-0}" \
            "${member_lists["$key"]:-}" \
            "$status_summary"
    done | sort -t $'\t' -k1,1 -k2,2
}

# ------------------------------------------------------------------------------
# Function: show_overview_table
# Purpose.: Display grouped overview as table
# Args....: $1 - tab-separated overview rows
# Returns.: 0
# Output..: overview table to stdout
# ------------------------------------------------------------------------------
show_overview_table() {
    local overview_rows="$1"
    local row_count
    row_count=$(printf '%s\n' "$overview_rows" | sed '/^$/d' | wc -l | tr -d '[:space:]')

    local total_sids=0
    local total_cdbroots=0
    local total_pdbs=0
    local total_targets=0
    local -A seen_clusters=()

    if [[ "$row_count" == "0" ]]; then
        log_info "No overview rows to display"
        return 0
    fi

    if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" && "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        printf "\n%-20s %-15s %8s %8s %8s %-18s %s\n" "Cluster" "SID" "CDBROOT" "PDBS" "TOTAL" "Status" "Members"
        printf "%-20s %-15s %8s %8s %8s %-18s %s\n" "--------------------" "---------------" "--------" "--------" "--------" "------------------" "------------------------------"
    elif [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
        printf "\n%-20s %-15s %8s %8s %8s %s\n" "Cluster" "SID" "CDBROOT" "PDBS" "TOTAL" "Status"
        printf "%-20s %-15s %8s %8s %8s %s\n" "--------------------" "---------------" "--------" "--------" "--------" "------------------"
    elif [[ "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        printf "\n%-20s %-15s %8s %8s %8s %s\n" "Cluster" "SID" "CDBROOT" "PDBS" "TOTAL" "Members"
        printf "%-20s %-15s %8s %8s %8s %s\n" "--------------------" "---------------" "--------" "--------" "--------" "------------------------------"
    else
        printf "\n%-20s %-15s %8s %8s %8s\n" "Cluster" "SID" "CDBROOT" "PDBS" "TOTAL"
        printf "%-20s %-15s %8s %8s %8s\n" "--------------------" "---------------" "--------" "--------" "--------"
    fi

    while IFS=$'\t' read -r cluster sid cdb_count pdb_count total_count members status_counts; do
        [[ -z "$cluster" && -z "$sid" ]] && continue

        total_sids=$((total_sids + 1))
        total_cdbroots=$((total_cdbroots + cdb_count))
        total_pdbs=$((total_pdbs + pdb_count))
        total_targets=$((total_targets + total_count))
        seen_clusters["$cluster"]=1

        local cluster_display="$cluster"
        local sid_display="$sid"
        if [[ ${#cluster_display} -gt 20 ]]; then
            cluster_display="${cluster_display:0:17}..."
        fi
        if [[ ${#sid_display} -gt 15 ]]; then
            sid_display="${sid_display:0:12}..."
        fi

        local members_display="$members"
        if [[ "$OVERVIEW_TRUNCATE_MEMBERS" == "true" && ${#members_display} -gt $OVERVIEW_MEMBERS_MAX_WIDTH ]]; then
            members_display="${members_display:0:$((OVERVIEW_MEMBERS_MAX_WIDTH - 3))}..."
        fi

        if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" && "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
            printf "%-20s %-15s %8d %8d %8d %-18s %s\n" "$cluster_display" "$sid_display" "$cdb_count" "$pdb_count" "$total_count" "${status_counts:--}" "$members_display"
        elif [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
            printf "%-20s %-15s %8d %8d %8d %s\n" "$cluster_display" "$sid_display" "$cdb_count" "$pdb_count" "$total_count" "${status_counts:--}"
        elif [[ "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
            printf "%-20s %-15s %8d %8d %8d %s\n" "$cluster_display" "$sid_display" "$cdb_count" "$pdb_count" "$total_count" "$members_display"
        else
            printf "%-20s %-15s %8d %8d %8d\n" "$cluster_display" "$sid_display" "$cdb_count" "$pdb_count" "$total_count"
        fi
    done <<< "$overview_rows"

    local total_clusters=${#seen_clusters[@]}

    printf "\n"
    printf "%-36s %10d\n" "Grand total of clusters" "$total_clusters"
    printf "%-36s %10d\n" "Grand total of Oracle SID" "$total_sids"
    printf "%-36s %10d\n" "Grand total of CDB root" "$total_cdbroots"
    printf "%-36s %10d\n" "Grand total of PDBs" "$total_pdbs"
    printf "%-36s %10d\n" "Grand total of targets" "$total_targets"

    if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
        printf "\n"
        printf "Legend: A=ACTIVE, N=NEEDS_ATTENTION, I=INACTIVE, U=UPDATING, R=REGISTERING, D=DELETING\n"
    fi

    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_overview_csv
# Purpose.: Display grouped overview as CSV
# Args....: $1 - tab-separated overview rows
# Returns.: 0
# Output..: CSV data to stdout
# ------------------------------------------------------------------------------
show_overview_csv() {
    local overview_rows="$1"

    if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" && "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            (split("\n") | map(select(length > 0) | split("\t"))) as $rows
            | (["cluster","sid","cdbroot_count","pdb_count","total_count","members","status_counts"] | @csv),
              ($rows[] | @csv)
        '
    elif [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            (split("\n") | map(select(length > 0) | split("\t") | [.[0], .[1], .[2], .[3], .[4], .[6]])) as $rows
            | (["cluster","sid","cdbroot_count","pdb_count","total_count","status_counts"] | @csv),
              ($rows[] | @csv)
        '
    elif [[ "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            (split("\n") | map(select(length > 0) | split("\t") | .[0:6])) as $rows
            | (["cluster","sid","cdbroot_count","pdb_count","total_count","members"] | @csv),
              ($rows[] | @csv)
        '
    else
        echo "$overview_rows" | jq -R -s '
            (split("\n") | map(select(length > 0) | split("\t") | .[0:5])) as $rows
            | (["cluster","sid","cdbroot_count","pdb_count","total_count"] | @csv),
              ($rows[] | @csv)
        '
    fi
}

# ------------------------------------------------------------------------------
# Function: show_overview_json
# Purpose.: Display grouped overview as JSON
# Args....: $1 - tab-separated overview rows
# Returns.: 0
# Output..: JSON array to stdout
# ------------------------------------------------------------------------------
show_overview_json() {
    local overview_rows="$1"

    if [[ "$OVERVIEW_INCLUDE_STATUS" == "true" && "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                cluster: .[0],
                sid: .[1],
                cdbroot_count: (.[2] | tonumber),
                pdb_count: (.[3] | tonumber),
                total_count: (.[4] | tonumber),
                members: (.[5] | if length == 0 then [] else split(",") end),
                status_counts: (.[6] | if length == 0 then {} else (split(",") | map(split("=")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries) end)
            })
        '
    elif [[ "$OVERVIEW_INCLUDE_STATUS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                cluster: .[0],
                sid: .[1],
                cdbroot_count: (.[2] | tonumber),
                pdb_count: (.[3] | tonumber),
                total_count: (.[4] | tonumber),
                status_counts: (.[6] | if length == 0 then {} else (split(",") | map(split("=")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries) end)
            })
        '
    elif [[ "$OVERVIEW_INCLUDE_MEMBERS" == "true" ]]; then
        echo "$overview_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                cluster: .[0],
                sid: .[1],
                cdbroot_count: (.[2] | tonumber),
                pdb_count: (.[3] | tonumber),
                total_count: (.[4] | tonumber),
                members: (.[5] | if length == 0 then [] else split(",") end)
            })
        '
    else
        echo "$overview_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                cluster: .[0],
                sid: .[1],
                cdbroot_count: (.[2] | tonumber),
                pdb_count: (.[3] | tonumber),
                total_count: (.[4] | tonumber)
            })
        '
    fi
}

# ------------------------------------------------------------------------------
# Function: show_overview
# Purpose.: Generate and display overview based on selected scope
# Args....: $1 - JSON data object with selected targets
# Returns.: 0
# Output..: Overview in requested format
# ------------------------------------------------------------------------------
show_overview() {
    local json_data="$1"
    local overview_rows

    overview_rows=$(build_overview_rows "$json_data")

    local selected_count
    selected_count=$(echo "$json_data" | jq '.data | length')

    if [[ "$selected_count" -gt 0 && "$OVERVIEW_PARSE_SKIPPED" -gt 0 ]]; then
        log_warn "Skipped $OVERVIEW_PARSE_SKIPPED target(s) due to name parsing mismatch. Configure DS_TARGET_NAME_REGEX if needed."
    fi

    case "$OUTPUT_FORMAT" in
        table)
            show_overview_table "$overview_rows"
            ;;
        json)
            show_overview_json "$overview_rows"
            ;;
        csv)
            show_overview_csv "$overview_rows"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: sanitize_tsv_field
# Purpose.: Sanitize string for TSV output
# Args....: $1 - raw value
# Returns.: 0
# Output..: sanitized value to stdout
# ------------------------------------------------------------------------------
sanitize_tsv_field() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\n'/ }"
    printf '%s' "$value"
}

# ------------------------------------------------------------------------------
# Function: health_issue_label
# Purpose.: Convert health issue code to human-readable label
# Args....: $1 - issue code
# Returns.: 0
# Output..: issue label to stdout
# ------------------------------------------------------------------------------
health_issue_label() {
    local issue_code="$1"

    case "$issue_code" in
        TARGET_NEEDS_ATTENTION_ACCOUNT_LOCKED)
            echo "Needs attention: account locked"
            ;;
        TARGET_NEEDS_ATTENTION_CREDENTIALS)
            echo "Needs attention: credential issue"
            ;;
        TARGET_NEEDS_ATTENTION_CONNECTIVITY)
            echo "Needs attention: connectivity/timeout"
            ;;
        TARGET_NEEDS_ATTENTION_FETCH_DETAILS)
            echo "Needs attention: fetch connection details"
            ;;
        TARGET_NEEDS_ATTENTION_OTHER)
            echo "Needs attention: other"
            ;;
        SID_MISSING_ROOT)
            echo "SID missing CDB root"
            ;;
        SID_DUPLICATE_ROOT)
            echo "SID has duplicate CDB roots"
            ;;
        SID_ROOT_WITHOUT_PDB)
            echo "SID root without PDB"
            ;;
        TARGET_NEEDS_ATTENTION)
            echo "Target needs attention"
            ;;
        TARGET_INACTIVE)
            echo "Target inactive"
            ;;
        TARGET_UNEXPECTED_STATE)
            echo "Target unexpected state"
            ;;
        TARGET_NAMING_NONSTANDARD)
            echo "Target naming non-standard"
            ;;
        *)
            echo "$issue_code"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: classify_needs_attention_issue
# Purpose.: Classify NEEDS_ATTENTION lifecycle-details into actionable issue type
# Args....: $1 - lifecycle-details reason
# Returns.: 0
# Output..: issue_code|severity|action
# ------------------------------------------------------------------------------
classify_needs_attention_issue() {
    local reason="$1"
    local reason_lc
    reason_lc=$(printf '%s' "$reason" | tr '[:upper:]' '[:lower:]')

    if [[ "$reason_lc" == *"ora-28000"* ]] || [[ "$reason_lc" == *"account is locked"* ]]; then
        echo "TARGET_NEEDS_ATTENTION_ACCOUNT_LOCKED|HIGH|Unlock/reset the DB account, then run ds_target_update_credentials.sh and ds_target_refresh.sh"
        return 0
    fi

    if [[ "$reason_lc" == *"ora-01017"* ]] || [[ "$reason_lc" == *"invalid username/password"* ]] || [[ "$reason_lc" == *"account has expired"* ]] || [[ "$reason_lc" == *"password must be changed"* ]]; then
        echo "TARGET_NEEDS_ATTENTION_CREDENTIALS|HIGH|Reset DB password if needed, update Data Safe credentials, then refresh target"
        return 0
    fi

    if [[ "$reason_lc" == *"failed to fetch connection details"* ]]; then
        echo "TARGET_NEEDS_ATTENTION_FETCH_DETAILS|MEDIUM|Verify connector/network and target connect details, then refresh target"
        return 0
    fi

    if [[ "$reason_lc" == *"login timeout"* ]] || [[ "$reason_lc" == *"failed to connect"* ]] || [[ "$reason_lc" == *"cannot connect"* ]]; then
        echo "TARGET_NEEDS_ATTENTION_CONNECTIVITY|MEDIUM|Check connector status, CMAN/network path, listener/service reachability, then refresh"
        return 0
    fi

    echo "TARGET_NEEDS_ATTENTION_OTHER|MEDIUM|Review lifecycle-details and run targeted refresh/credential/connector checks"
}

# ------------------------------------------------------------------------------
# Function: is_health_normal_state
# Purpose.: Check if lifecycle-state is considered normal
# Args....: $1 - lifecycle state
# Returns.: 0 if normal, 1 otherwise
# ------------------------------------------------------------------------------
is_health_normal_state() {
    local lifecycle_state="$1"
    local normal_states=",${HEALTH_NORMAL_STATES},"
    [[ "$normal_states" == *",${lifecycle_state},"* ]]
}

# ------------------------------------------------------------------------------
# Function: evaluate_health_issues
# Purpose.: Evaluate selected targets for troubleshooting anomalies
# Args....: $1 - JSON data object with selected targets
# Returns.: 0
# Output..: TSV issue rows: type,severity,cluster,sid,target,state,reason,action
# ------------------------------------------------------------------------------
evaluate_health_issues() {
    local json_data="$1"

    local -A sid_cluster=()
    local -A sid_root_count=()
    local -A sid_pdb_count=()

    while IFS=$'\t' read -r target_name lifecycle_state lifecycle_reason; do
        [[ -z "$target_name" ]] && continue

        local parsed
        local cluster="-"
        local sid="-"

        if parsed=$(parse_target_name_components "$target_name"); then
            local db_token
            IFS=$'\t' read -r cluster sid db_token <<< "$parsed"
            local sid_key="${cluster}|${sid}"
            sid_cluster["$sid_key"]="$cluster"

            if is_cdbroot_name "$db_token"; then
                sid_root_count["$sid_key"]=$((${sid_root_count["$sid_key"]:-0} + 1))
            else
                sid_pdb_count["$sid_key"]=$((${sid_pdb_count["$sid_key"]:-0} + 1))
            fi
        else
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "TARGET_NAMING_NONSTANDARD" \
                "MEDIUM" \
                "-" \
                "-" \
                "$(sanitize_tsv_field "$target_name")" \
                "$(sanitize_tsv_field "$lifecycle_state")" \
                "Target name does not match configured naming standard" \
                "Set DS_TARGET_NAME_REGEX or DS_TARGET_NAME_SID_REGEX and validate target naming"
        fi

        case "$lifecycle_state" in
            NEEDS_ATTENTION)
                local na_reason na_meta na_issue na_severity na_action
                na_reason="${lifecycle_reason:-No lifecycle details provided}"
                na_meta=$(classify_needs_attention_issue "$na_reason")
                IFS='|' read -r na_issue na_severity na_action <<< "$na_meta"

                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$na_issue" \
                    "$na_severity" \
                    "$(sanitize_tsv_field "$cluster")" \
                    "$(sanitize_tsv_field "$sid")" \
                    "$(sanitize_tsv_field "$target_name")" \
                    "$(sanitize_tsv_field "$lifecycle_state")" \
                    "$(sanitize_tsv_field "$na_reason")" \
                    "$na_action"
                ;;
            INACTIVE)
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "TARGET_INACTIVE" \
                    "MEDIUM" \
                    "$(sanitize_tsv_field "$cluster")" \
                    "$(sanitize_tsv_field "$sid")" \
                    "$(sanitize_tsv_field "$target_name")" \
                    "$(sanitize_tsv_field "$lifecycle_state")" \
                    "Target is inactive" \
                    "Use ds_target_activate.sh for this scope/target"
                ;;
            *)
                if ! is_health_normal_state "$lifecycle_state"; then
                    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                        "TARGET_UNEXPECTED_STATE" \
                        "MEDIUM" \
                        "$(sanitize_tsv_field "$cluster")" \
                        "$(sanitize_tsv_field "$sid")" \
                        "$(sanitize_tsv_field "$target_name")" \
                        "$(sanitize_tsv_field "$lifecycle_state")" \
                        "State is outside normal states (${HEALTH_NORMAL_STATES})" \
                        "Wait/poll state, then refresh or retry operation for this target"
                fi
                ;;
        esac
    done < <(echo "$json_data" | jq -r '.data[] | [."display-name" // "", ."lifecycle-state" // "UNKNOWN", ."lifecycle-details" // ""] | @tsv')

    local sid_key
    for sid_key in "${!sid_cluster[@]}"; do
        local cluster sid root_count pdb_count
        IFS='|' read -r cluster sid <<< "$sid_key"
        root_count=${sid_root_count["$sid_key"]:-0}
        pdb_count=${sid_pdb_count["$sid_key"]:-0}

        if ((pdb_count > 0 && root_count == 0)); then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "SID_MISSING_ROOT" \
                "HIGH" \
                "$(sanitize_tsv_field "$cluster")" \
                "$(sanitize_tsv_field "$sid")" \
                "-" \
                "-" \
                "SID has ${pdb_count} PDB target(s) but no CDB root target" \
                "Register or refresh the CDB root target for this SID"
        fi

        if ((root_count > 1)); then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "SID_DUPLICATE_ROOT" \
                "HIGH" \
                "$(sanitize_tsv_field "$cluster")" \
                "$(sanitize_tsv_field "$sid")" \
                "-" \
                "-" \
                "SID has ${root_count} CDB root targets" \
                "Review duplicate root registrations and keep only one valid root"
        fi

        if ((root_count > 0 && pdb_count == 0)); then
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "SID_ROOT_WITHOUT_PDB" \
                "LOW" \
                "$(sanitize_tsv_field "$cluster")" \
                "$(sanitize_tsv_field "$sid")" \
                "-" \
                "-" \
                "SID has root target but no PDB targets" \
                "Verify whether PDB targets should exist and register missing PDBs if needed"
        fi
    done
}

# ------------------------------------------------------------------------------
# Function: show_health_overview_table
# Purpose.: Display summarized health issue overview
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: Health summary table
# ------------------------------------------------------------------------------
show_health_overview_table() {
    local issue_rows="$1"

    if [[ -z "$issue_rows" ]]; then
        printf "\nNo health issues detected for selected scope.\n\n"
        return 0
    fi

    local grouped
    grouped=$(echo "$issue_rows" | jq -R -s '
        def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
        split("\n")
        | map(select(length > 0) | split("\t"))
        | map({type: .[0], severity: .[1], sid: .[3], action: .[7]})
        | group_by(.type)
        | map({
            type: .[0].type,
            severity: (map(.severity) | max_by(sev_rank)),
            count: length,
            sid_count: (map(.sid) | map(select(. != "-" and . != "")) | unique | length),
            action: .[0].action
          })
                | sort_by(-(.severity|sev_rank), -.count, -.sid_count, .type)
    ')

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        printf "\n%-44s %-8s %8s %8s %s\n" "Issue" "Severity" "Count" "SIDs" "Suggested Action"
        printf "%-44s %-8s %8s %8s %s\n" "--------------------------------------------" "--------" "--------" "--------" "------------------------------"
        echo "$grouped" | jq -r '.[] | [.type, .severity, (.count|tostring), (.sid_count|tostring), .action] | @tsv' \
            | while IFS=$'\t' read -r issue_type severity count sid_count action; do
                local issue_display
                issue_display="$(health_issue_label "$issue_type")"
                if [[ ${#issue_display} -gt 44 ]]; then
                    issue_display="${issue_display:0:41}..."
                fi
                printf "%-44s %-8s %8d %8d %s\n" "$issue_display" "$severity" "$count" "$sid_count" "$action"
            done
    else
        printf "\n%-44s %-8s %8s %8s\n" "Issue" "Severity" "Count" "SIDs"
        printf "%-44s %-8s %8s %8s\n" "--------------------------------------------" "--------" "--------" "--------"
        echo "$grouped" | jq -r '.[] | [.type, .severity, (.count|tostring), (.sid_count|tostring)] | @tsv' \
            | while IFS=$'\t' read -r issue_type severity count sid_count; do
                local issue_display
                issue_display="$(health_issue_label "$issue_type")"
                if [[ ${#issue_display} -gt 44 ]]; then
                    issue_display="${issue_display:0:41}..."
                fi
                printf "%-44s %-8s %8d %8d\n" "$issue_display" "$severity" "$count" "$sid_count"
            done
    fi
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_health_details_table
# Purpose.: Display health issue drill-down details
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: Detailed health issue table
# ------------------------------------------------------------------------------
show_health_details_table() {
    local issue_rows="$1"

    if [[ -z "$issue_rows" ]]; then
        return 0
    fi

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        printf "%-33s %-8s %-20s %-15s %-42s %-16s %-44s %s\n" "Issue" "Severity" "Cluster" "SID" "Target" "State" "Reason" "Suggested Action"
        printf "%-33s %-8s %-20s %-15s %-42s %-16s %-44s %s\n" "---------------------------------" "--------" "--------------------" "---------------" "------------------------------------------" "----------------" "--------------------------------------------" "------------------------------"
        echo "$issue_rows" | while IFS=$'\t' read -r issue_type severity cluster sid target state reason action; do
            [[ -z "$issue_type" ]] && continue
            printf "%-33s %-8s %-20s %-15s %-42s %-16s %-44s %s\n" \
                "$(health_issue_label "$issue_type")" \
                "$severity" \
                "${cluster:0:20}" \
                "${sid:0:15}" \
                "${target:0:42}" \
                "${state:0:16}" \
                "${reason:0:44}" \
                "$action"
        done
    else
        printf "%-33s %-8s %-20s %-15s %-42s %-16s %s\n" "Issue" "Severity" "Cluster" "SID" "Target" "State" "Reason"
        printf "%-33s %-8s %-20s %-15s %-42s %-16s %s\n" "---------------------------------" "--------" "--------------------" "---------------" "------------------------------------------" "----------------" "--------------------------------------------"
        echo "$issue_rows" | while IFS=$'\t' read -r issue_type severity cluster sid target state reason _action; do
            [[ -z "$issue_type" ]] && continue
            printf "%-33s %-8s %-20s %-15s %-42s %-16s %s\n" \
                "$(health_issue_label "$issue_type")" \
                "$severity" \
                "${cluster:0:20}" \
                "${sid:0:15}" \
                "${target:0:42}" \
                "${state:0:16}" \
                "${reason:0:44}"
        done
    fi

    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_health_overview_json
# Purpose.: Output summarized health issues as JSON
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: JSON array
# ------------------------------------------------------------------------------
show_health_overview_json() {
    local issue_rows="$1"

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        echo "$issue_rows" | jq -R -s '
            def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({type: .[0], severity: .[1], sid: .[3], action: .[7]})
            | group_by(.type)
            | map({
                issue: .[0].type,
                severity: (map(.severity) | max_by(sev_rank)),
                count: length,
                sid_count: (map(.sid) | map(select(. != "-" and . != "")) | unique | length),
                action: .[0].action
              })
            | sort_by(-(.severity|sev_rank), -.count, -.sid_count, .issue)
        '
    else
        echo "$issue_rows" | jq -R -s '
            def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({type: .[0], severity: .[1], sid: .[3]})
            | group_by(.type)
            | map({
                issue: .[0].type,
                severity: (map(.severity) | max_by(sev_rank)),
                count: length,
                sid_count: (map(.sid) | map(select(. != "-" and . != "")) | unique | length)
              })
            | sort_by(-(.severity|sev_rank), -.count, -.sid_count, .issue)
        '
    fi
}

# ------------------------------------------------------------------------------
# Function: show_health_overview_csv
# Purpose.: Output summarized health issues as CSV
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: CSV
# ------------------------------------------------------------------------------
show_health_overview_csv() {
    local issue_rows="$1"

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        echo "$issue_rows" | jq -R -s '
            def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({type: .[0], severity: .[1], sid: .[3], action: .[7]})
            | group_by(.type)
            | map([
                .[0].type,
                (map(.severity) | max_by(sev_rank)),
                (length|tostring),
                ((map(.sid) | map(select(. != "-" and . != "")) | unique | length)|tostring),
                .[0].action
              ])
            | sort_by(-(.[1]|sev_rank), -(.[2]|tonumber), -(.[3]|tonumber), .[0])
            | (["issue","severity","count","sid_count","action"] | @csv), (.[] | @csv)
        '
    else
        echo "$issue_rows" | jq -R -s '
            def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({type: .[0], severity: .[1], sid: .[3]})
            | group_by(.type)
            | map([
                .[0].type,
                (map(.severity) | max_by(sev_rank)),
                (length|tostring),
                ((map(.sid) | map(select(. != "-" and . != "")) | unique | length)|tostring)
              ])
                        | sort_by(-(.[1]|sev_rank), -(.[2]|tonumber), -(.[3]|tonumber), .[0])
            | (["issue","severity","count","sid_count"] | @csv), (.[] | @csv)
        '
    fi
}

# ------------------------------------------------------------------------------
# Function: show_health_details_json
# Purpose.: Output detailed health issues as JSON
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: JSON array
# ------------------------------------------------------------------------------
show_health_details_json() {
    local issue_rows="$1"

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        echo "$issue_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                issue: .[0],
                severity: .[1],
                cluster: .[2],
                sid: .[3],
                target: .[4],
                state: .[5],
                reason: .[6],
                action: .[7]
              })
        '
    else
        echo "$issue_rows" | jq -R -s '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                issue: .[0],
                severity: .[1],
                cluster: .[2],
                sid: .[3],
                target: .[4],
                state: .[5],
                reason: .[6]
              })
        '
    fi
}

# ------------------------------------------------------------------------------
# Function: show_health_details_csv
# Purpose.: Output detailed health issues as CSV
# Args....: $1 - TSV issue rows
# Returns.: 0
# Output..: CSV
# ------------------------------------------------------------------------------
show_health_details_csv() {
    local issue_rows="$1"

    if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
        echo "issue,severity,cluster,sid,target,state,reason,action"
        echo "$issue_rows" | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | .[] | @csv'
    else
        echo "issue,severity,cluster,sid,target,state,reason"
        echo "$issue_rows" | jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | .[0:7]) | .[] | @csv'
    fi
}

# ------------------------------------------------------------------------------
# Function: show_health
# Purpose.: Display health/troubleshooting analysis for selected scope
# Args....: $1 - JSON data object with selected targets
# Returns.: 0
# Output..: Health overview and optional details
# ------------------------------------------------------------------------------
show_health() {
    local json_data="$1"
    local issue_rows

    issue_rows=$(evaluate_health_issues "$json_data")

    case "$OUTPUT_FORMAT" in
        table)
            show_health_overview_table "$issue_rows"
            if [[ "$SHOW_HEALTH_DETAILS" == "true" ]]; then
                show_health_details_table "$issue_rows"
            fi
            ;;
        json)
            if [[ "$SHOW_HEALTH_DETAILS" == "true" ]]; then
                show_health_details_json "$issue_rows"
            else
                show_health_overview_json "$issue_rows"
            fi
            ;;
        csv)
            if [[ "$SHOW_HEALTH_DETAILS" == "true" ]]; then
                show_health_details_csv "$issue_rows"
            else
                show_health_overview_csv "$issue_rows"
            fi
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: apply_target_filter
# Purpose.: Filter target JSON by display-name regex
# Args....: $1 - JSON data object with .data array
# Returns.: 0 on success
# Output..: Filtered JSON data object
# ------------------------------------------------------------------------------
apply_target_filter() {
    local json_data="$1"

    if [[ -z "$TARGET_FILTER" ]]; then
        echo "$json_data"
        return 0
    fi

    echo "$json_data" | jq --arg re "$TARGET_FILTER" '.data = (.data | map(select((."display-name" // "") | test($re))))'
}

# ------------------------------------------------------------------------------
# Function: list_targets_in_compartment
# Purpose.: List all targets in compartment
# Args....: $1 - compartment OCID or name
# Returns.: 0 on success, 1 on error
# Output..: JSON array of targets to stdout
# ------------------------------------------------------------------------------
list_targets_in_compartment() {
    local compartment="$1"
    local comp_ocid

    comp_ocid=$(oci_resolve_compartment_ocid "$compartment") || return 1

    log_debug "Listing targets in compartment OCID: $comp_ocid"

    local -a cmd=(
        data-safe target-database list
        --compartment-id "$comp_ocid"
        --compartment-id-in-subtree true
        --all
    )

    if [[ -n "$LIFECYCLE_STATE" ]]; then
        cmd+=(--lifecycle-state "$LIFECYCLE_STATE")
        log_debug "Filtering by lifecycle state: $LIFECYCLE_STATE"
    fi

    oci_exec "${cmd[@]}"
}

# ------------------------------------------------------------------------------
# Function: get_target_details
# Purpose.: Get details for specific target
# Args....: $1 - target OCID
# Returns.: 0 on success, 1 on error
# Output..: JSON object to stdout
# ------------------------------------------------------------------------------
get_target_details() {
    local target_ocid="$1"

    log_debug "Getting details for: $target_ocid"

    oci_exec data-safe target-database get \
        --target-database-id "$target_ocid" \
        --query 'data'
}

# ------------------------------------------------------------------------------
# Function: show_count_summary
# Purpose.: Display count summary grouped by lifecycle state
# Args....: $1 - JSON data
# Returns.: 0 on success
# Output..: Formatted summary table to stdout
# ------------------------------------------------------------------------------
show_count_summary() {
    local json_data="$1"

    log_info "Data Safe targets summary by lifecycle state"

    # Extract and count lifecycle states
    local counts
    counts=$(echo "$json_data" | jq -r '.data[]."lifecycle-state"' | sort | uniq -c | sort -rn)

    if [[ -z "$counts" ]]; then
        log_info "No targets found"
        return 0
    fi

    # Print table header
    printf "\n%-20s %10s\n" "Lifecycle State" "Count"
    printf "%-20s %10s\n" "-------------------" "----------"

    # Print counts
    local total=0
    while read -r count state; do
        printf "%-20s %10d\n" "$state" "$count"
        total=$((total + count))
    done <<< "$counts"

    printf "%-20s %10s\n" "-------------------" "----------"
    printf "%-20s %10d\n" "TOTAL" "$total"
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_details_table
# Purpose.: Display detailed target information in table format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: Formatted table to stdout
# ------------------------------------------------------------------------------
show_details_table() {
    local json_data="$1"
    local fields="$2"

    # Convert fields to jq array format
    local -a field_array field_widths
    IFS=',' read -ra field_array <<< "$fields"

    # Set column widths (display-name gets more space, lifecycle-details in problems mode gets even more)
    for field in "${field_array[@]}"; do
        if [[ "$field" == "display-name" ]]; then
            field_widths+=(50)
        elif [[ "$field" == "lifecycle-details" && "$SHOW_PROBLEMS" == "true" ]]; then
            field_widths+=(80)
        else
            field_widths+=(30)
        fi
    done

    # Build jq select expression
    local jq_select="["
    for field in "${field_array[@]}"; do
        jq_select+=".[\"${field}\"],"
    done
    jq_select="${jq_select%,}]"

    # Print header
    printf "\n"
    local idx=0
    for field in "${field_array[@]}"; do
        printf "%-${field_widths[$idx]}s " "$field"
        idx=$((idx + 1))
    done
    printf "\n"

    idx=0
    for field in "${field_array[@]}"; do
        local width=${field_widths[$idx]}
        printf "%-${width}s " "$(printf "%0.s-" $(seq 1 "$width"))"
        idx=$((idx + 1))
    done
    printf "\n"

    # Print data
    echo "$json_data" | jq -r ".data[] | $jq_select | @tsv" \
        | while IFS=$'\t' read -r -a values; do
            local idx=0
            for value in "${values[@]}"; do
                local width=${field_widths[$idx]}
                local max_len=$((width - 2))

                # Don't truncate lifecycle-details in problems mode
                local current_field="${field_array[$idx]}"
                if [[ "$current_field" == "lifecycle-details" && "$SHOW_PROBLEMS" == "true" ]]; then
                    printf "%-${width}s " "$value"
                else
                    # Truncate long values
                    local display_value="${value:0:$max_len}"
                    [[ ${#value} -gt $max_len ]] && display_value="${display_value}.."
                    printf "%-${width}s " "$display_value"
                fi
                idx=$((idx + 1))
            done
            printf "\n"
        done

    # Print count
    local count
    count=$(echo "$json_data" | jq '.data | length')
    printf "\nTotal: %d targets\n\n" "$count"
}

# ------------------------------------------------------------------------------
# Function: show_details_json
# Purpose.: Display detailed target information in JSON format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: JSON output to stdout
# ------------------------------------------------------------------------------
show_details_json() {
    local json_data="$1"
    local fields="$2"

    if [[ "$fields" == "all" || -z "$fields" ]]; then
        echo "$json_data" | jq '.data[]'
    else
        # Build jq select expression for specific fields
        local jq_expr="{"
        IFS=',' read -ra field_array <<< "$fields"
        for field in "${field_array[@]}"; do
            jq_expr+="\"${field}\": .[\"${field}\"],"
        done
        jq_expr="${jq_expr%,}}"

        echo "$json_data" | jq ".data[] | $jq_expr"
    fi
}

# ------------------------------------------------------------------------------
# Function: show_details_csv
# Purpose.: Display detailed target information in CSV format
# Args....: $1 - JSON data
#           $2 - fields (comma-separated)
# Returns.: 0 on success
# Output..: CSV output to stdout
# ------------------------------------------------------------------------------
show_details_csv() {
    local json_data="$1"
    local fields="$2"

    # Print header
    echo "$fields"

    # Convert fields to jq array
    local -a field_array
    IFS=',' read -ra field_array <<< "$fields"

    local jq_select="["
    for field in "${field_array[@]}"; do
        jq_select+=".[\"${field}\"],"
    done
    jq_select="${jq_select%,}]"

    # Print data
    echo "$json_data" | jq -r ".data[] | $jq_select | @csv"
}

# ------------------------------------------------------------------------------
# Function: show_problems_grouped
# Purpose.: Display NEEDS_ATTENTION targets grouped by problem type
# Args....: $1 - JSON data
#           $2 - output format (table|json|csv)
# Returns.: 0 on success
# Output..: Grouped problem summary to stdout
# ------------------------------------------------------------------------------
show_problems_grouped() {
    local json_data="$1"
    local output_format="${2:-table}"

    log_info "Grouping NEEDS_ATTENTION targets by problem type"

    # Extract and group by lifecycle-details, filtering out nulls and empty strings
    local grouped_json
    grouped_json=$(echo "$json_data" | jq -r '
        .data 
        | map(select(."lifecycle-details" != null and ."lifecycle-details" != ""))
        | group_by(."lifecycle-details") 
        | map({problem: (.[0]."lifecycle-details" // "Unknown"), count: length, targets: [.[] | ."display-name"]})
        | sort_by(-.count)
    ')

    case "$output_format" in
        json)
            echo "$grouped_json" | jq '.'
            ;;
        csv)
            echo "problem,count,targets"
            echo "$grouped_json" | jq -r '.[] | [.problem, .count, (.targets | join("; "))] | @csv'
            ;;
        table | *)
            printf "\n"
            printf "%-70s %10s\n" "Problem Type" "Count"
            printf "%-70s %10s\n" "$(printf '%0.s-' {1..70})" "----------"

            # Use jq to output JSON and parse it more safely
            echo "$grouped_json" | jq -r '.[] | @base64' | while read -r line; do
                local problem count
                problem=$(echo "$line" | base64 -d 2> /dev/null | jq -r '.problem // "Unknown"')
                count=$(echo "$line" | base64 -d 2> /dev/null | jq -r '.count // 0')

                # Truncate problem to fit column width (68 chars to leave space)
                if [[ ${#problem} -gt 68 ]]; then
                    problem="${problem:0:65}..."
                fi

                # Validate count is a number
                if [[ "$count" =~ ^[0-9]+$ ]]; then
                    printf "%-70s %10d\n" "$problem" "$count"
                else
                    log_warn "Invalid count for problem: $problem (count: $count)"
                fi
            done

            local total
            total=$(echo "$json_data" | jq '.data | length')
            printf "\n%-70s %10d\n" "Total NEEDS_ATTENTION targets" "$total"

            # Show detailed target list per problem if requested
            if [[ "$SHOW_DETAILS" == "true" ]]; then
                printf "\n"
                echo "$grouped_json" | jq -r '.[] | "\n\(.problem) (\(.count) targets):\n  - \(.targets | join("\n  - "))"'
            fi
            printf "\n"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - orchestrates target listing and display
# Returns.: 0 on success, 1 on error
# Output..: Target information based on selected format and mode
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function: do_work
# Purpose.: Main work function - fetch and display targets
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Target list in requested format
# ------------------------------------------------------------------------------
do_work() {
    local json_data

    if [[ -n "$TARGETS" ]]; then
        log_info "Fetching details for specific targets..."
    else
        log_info "Listing targets in compartment hierarchy"
    fi

    json_data=$(ds_collect_targets "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER") || die "Failed to collect targets"

    if [[ -n "$TARGET_FILTER" ]]; then
        local filtered_count
        filtered_count=$(echo "$json_data" | jq '.data | length')
        if [[ "$filtered_count" -eq 0 ]]; then
            log_info "No targets matched filter regex: $TARGET_FILTER"
        fi
    fi

    # Display results based on mode
    if [[ "$SHOW_HEALTH_OVERVIEW" == "true" ]]; then
        show_health "$json_data"
    elif [[ "$SHOW_COUNT" == "true" ]]; then
        show_count_summary "$json_data"
    elif [[ "$SHOW_OVERVIEW" == "true" ]]; then
        show_overview "$json_data"
    elif [[ "$GROUP_PROBLEMS" == "true" ]]; then
        show_problems_grouped "$json_data" "$OUTPUT_FORMAT"
    else
        case "$OUTPUT_FORMAT" in
            table)
                show_details_table "$json_data" "$FIELDS"
                ;;
            json)
                show_details_json "$json_data" "$FIELDS"
                ;;
            csv)
                show_details_csv "$json_data" "$FIELDS"
                ;;
        esac
    fi
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
    do_work

    log_info "List completed successfully"
}

# Parse arguments and run
parse_args "$@"
main

# --- End of ds_target_list.sh -------------------------------------------------
