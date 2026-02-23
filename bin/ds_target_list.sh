#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_list.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.23
# Version....: v0.16.2
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
: "${INPUT_JSON:=}"
: "${SAVE_JSON:=}"
: "${OUTPUT_FORMAT:=table}" # table|json|csv
: "${MODE:=details}" # details|count|overview|health|problems|report
: "${ISSUE_VIEW:=summary}" # summary|details
: "${HEALTH_SCOPE:=all}" # all|needs_attention
: "${FIELDS:=display-name,lifecycle-state,infrastructure-type}"
: "${OVERVIEW_INCLUDE_STATUS:=true}"
: "${OVERVIEW_INCLUDE_MEMBERS:=true}"
: "${OVERVIEW_TRUNCATE_MEMBERS:=true}"
: "${OVERVIEW_MEMBERS_MAX_WIDTH:=80}"
: "${SHOW_HEALTH_DETAILS:=false}"
: "${SHOW_HEALTH_ACTIONS:=true}"
: "${HEALTH_ISSUE_FILTER:=}"
: "${HEALTH_NORMAL_STATES:=ACTIVE,UPDATING}"
: "${DS_TARGET_NAME_REGEX:=}"
: "${DS_TARGET_NAME_SEPARATOR:=_}"
: "${DS_TARGET_NAME_ROOT_LABEL:=CDB\$ROOT}"
: "${DS_TARGET_NAME_CDBROOT_REGEX:=^(CDB\\\$ROOT|CDBROOT)$}"
: "${DS_TARGET_NAME_SID_REGEX:=^cdb[0-9]+[[:alnum:]]*$}"
: "${REPORT_RAW_TARGETS:=0}"
: "${REPORT_SELECTED_TARGETS:=0}"
: "${REPORT_SCOPE_TYPE:=}"
: "${REPORT_SCOPE_LABEL:=}"
: "${REPORT_COMPARTMENT_OCID:=}"
: "${REPORT_COMPARTMENT_NAME:=}"
: "${REPORT_FILTERS:=none}"
: "${REPORT_SCOPE_KEY:=}"
: "${COLLECTED_JSON_DATA:=}"

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
    -T, --targets LIST                  Comma-separated target names or OCIDs
    -r, --filter REGEX                  Filter target names by regex (substring match)
    -L, --lifecycle STATE               Filter by lifecycle state (ACTIVE, NEEDS_ATTENTION, etc.)
    --input-json FILE                   Load selected target JSON from file (skip OCI fetch)
    --save-json FILE                    Save selected target JSON to file for reuse

    Output:
        Mode selection (single entry point):
        -M, --mode MODE                 details|count|overview|health|problems|report
                                            details: default target list
                                            count: lifecycle summary counts
                                            overview: grouped cluster/SID landscape
                                            health: full troubleshooting issue model
                                            problems: focused issue model (NEEDS_ATTENTION/INACTIVE/UNEXPECTED_STATE)
                                            report: one-page high-level consolidated summary
            --count                     Alias for --mode count
            --problems                  Alias for --mode problems
            --overview                  Alias for --mode overview
            --health                    Alias for --mode health
            --report                    Alias for --mode report
            --details                   Alias for --mode details (default)

    Troubleshooting drill-down (for --mode health|problems):
            --issue-view VIEW               summary|details (default: summary)
            --issue ISSUE                   Filter to one issue (code or label text)
            --action                        Include suggested actions (default)
            --no-action                     Hide suggested actions

    Overview options (only with --mode overview):
        --status                            Include lifecycle counts per SID row (default)
        --no-status                         Hide lifecycle counts in overview output
        --no-members                        Hide member/PDB names in overview output
        --truncate-members                  Truncate member/PDB list in table output (default)
        --no-truncate-members               Show full member/PDB list in table output

    Format and fields:
    -f, --format FMT                        Output format: table|json|csv (default: table)
    -F, --fields FIELDS                     Comma-separated fields for details (default: ${FIELDS})

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
    ${SCRIPT_NAME} --mode count

    # Grouped landscape overview
    ${SCRIPT_NAME} --mode overview

    # Full health issue summary across all issue types
    ${SCRIPT_NAME} --mode health

    # NEEDS_ATTENTION-focused problem summary
    ${SCRIPT_NAME} --mode problems

    # One-page consolidated high-level report
    ${SCRIPT_NAME} --mode report

    # Reuse a previously saved selection payload
    ${SCRIPT_NAME} --input-json ./target_selection.json --mode report

    # Save selected targets for further processing
    ${SCRIPT_NAME} --save-json ./target_selection.json --mode overview

    # Drill down to one issue topic
    ${SCRIPT_NAME} --mode health --issue-view details --issue "SID missing CDB root"

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
            -M | --mode)
                need_val "$1" "${2:-}"
                MODE="$2"
                shift 2
                ;;
            --count)
                MODE="count"
                shift
                ;;
            --problems)
                MODE="problems"
                shift
                ;;
            --overview)
                MODE="overview"
                shift
                ;;
            --health)
                MODE="health"
                shift
                ;;
            --report)
                MODE="report"
                shift
                ;;
            --details)
                MODE="details"
                shift
                ;;
            --status)
                OVERVIEW_INCLUDE_STATUS=true
                shift
                ;;
            --no-status)
                OVERVIEW_INCLUDE_STATUS=false
                shift
                ;;
            --no-members)
                OVERVIEW_INCLUDE_MEMBERS=false
                shift
                ;;
            --truncate-members)
                OVERVIEW_TRUNCATE_MEMBERS=true
                shift
                ;;
            --no-truncate-members)
                OVERVIEW_TRUNCATE_MEMBERS=false
                shift
                ;;
            --issue)
                need_val "$1" "${2:-}"
                HEALTH_ISSUE_FILTER="$2"
                shift 2
                ;;
            --issue-view)
                need_val "$1" "${2:-}"
                ISSUE_VIEW="$2"
                shift 2
                ;;
            --action)
                SHOW_HEALTH_ACTIONS=true
                shift
                ;;
            --no-action)
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

    # Validate consolidated mode
    case "${MODE}" in
        details | count | overview | health | problems | report) : ;;
        *) die "Invalid mode: '${MODE}'. Use details, count, overview, health, problems, or report" ;;
    esac

    # Validate issue view mode
    case "${ISSUE_VIEW}" in
        summary | details) : ;;
        *) die "Invalid issue view: '${ISSUE_VIEW}'. Use summary or details" ;;
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
    local used_default_root_scope="false"

    if [[ -z "$INPUT_JSON" ]]; then
        require_oci_cli

        COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

        if [[ "$SELECT_ALL" == "true" ]]; then
            log_info "Using DS_ROOT_COMP scope via --all"
            REPORT_SCOPE_TYPE="--all"
        fi

        # Resolve compartment using new pattern: explicit -c > DS_ROOT_COMP > error
        if [[ -z "$TARGETS" && -z "$COMPARTMENT" ]]; then
            used_default_root_scope="true"
            COMPARTMENT=$(resolve_compartment_for_operation "$COMPARTMENT") || die "Failed to resolve compartment. Set DS_ROOT_COMP in .env or datasafe.conf (see --help for details) or use -c/--compartment"

            # Get compartment name for display
            local comp_name
            comp_name=$(oci_get_compartment_name "$COMPARTMENT") || comp_name="<unknown>"
            REPORT_COMPARTMENT_NAME="$comp_name"
            REPORT_COMPARTMENT_OCID="$COMPARTMENT"

            log_debug "Using root compartment OCID: $COMPARTMENT"
            log_info "Using root compartment: $comp_name (includes sub-compartments)"
        fi
    else
        log_info "Using input JSON file: $INPUT_JSON"
        REPORT_SCOPE_TYPE="--input-json"
        REPORT_SCOPE_LABEL="$INPUT_JSON"
    fi

    if [[ -z "$REPORT_SCOPE_TYPE" ]]; then
        if [[ -n "$TARGETS" ]]; then
            REPORT_SCOPE_TYPE="--targets"
            REPORT_SCOPE_LABEL="$TARGETS"
        elif [[ "$SELECT_ALL" == "true" ]]; then
            REPORT_SCOPE_TYPE="--all"
            REPORT_SCOPE_LABEL="DS_ROOT_COMP"
        else
            REPORT_SCOPE_TYPE="compartment"
            if [[ "$used_default_root_scope" == "true" ]]; then
                REPORT_SCOPE_LABEL="DS_ROOT_COMP"
            else
                REPORT_SCOPE_LABEL="${COMPARTMENT:-DS_ROOT_COMP}"
            fi
        fi
    fi

    if [[ -n "$TARGET_FILTER" ]]; then
        REPORT_SCOPE_TYPE+=" + --filter"
    fi

    if [[ -n "$LIFECYCLE_STATE" ]]; then
        REPORT_SCOPE_TYPE+=" + --lifecycle"
    fi

    if [[ -z "$REPORT_COMPARTMENT_OCID" && -n "$COMPARTMENT" ]]; then
        REPORT_COMPARTMENT_OCID="$COMPARTMENT"
    fi

    if [[ -z "$REPORT_COMPARTMENT_NAME" && -n "$COMPARTMENT" && "$COMPARTMENT" != ocid1.* ]]; then
        REPORT_COMPARTMENT_NAME="$COMPARTMENT"
    fi

    local -a filters=()
    [[ -n "$TARGET_FILTER" ]] && filters+=("regex:${TARGET_FILTER}")
    [[ -n "$LIFECYCLE_STATE" ]] && filters+=("lifecycle:${LIFECYCLE_STATE}")
    if [[ ${#filters[@]} -gt 0 ]]; then
        REPORT_FILTERS=$(join_by "; " "${filters[@]}")
    else
        REPORT_FILTERS="none"
    fi

    REPORT_SCOPE_KEY="${REPORT_SCOPE_TYPE}|${REPORT_SCOPE_LABEL}|${REPORT_COMPARTMENT_OCID}|${REPORT_FILTERS}"

    # Normalize mode-specific scope
    HEALTH_SCOPE="all"

    case "${MODE}" in
        health)
            ;;
        problems)
            HEALTH_SCOPE="needs_attention"
            ;;
        details)
            :
            ;;
        count | overview | report)
            :
            ;;
    esac

    if [[ -n "$INPUT_JSON" ]]; then
        if [[ -n "$TARGETS" || -n "$COMPARTMENT" || "$SELECT_ALL" == "true" ]]; then
            log_warn "--input-json is set: ignoring OCI selection flags (-A/--all, -c/--compartment, -T/--targets)"
        fi

        [[ -f "$INPUT_JSON" ]] || die "Input JSON file not found: $INPUT_JSON"
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file is not readable: $INPUT_JSON"
    fi

    if [[ "$ISSUE_VIEW" == "details" ]]; then
        SHOW_HEALTH_DETAILS=true
    else
        SHOW_HEALTH_DETAILS=false
    fi

    # Count mode doesn't work with specific targets
    if [[ "$MODE" == "count" && -n "$TARGETS" ]]; then
        die "Count mode (--mode count) cannot be used with specific targets (-T). Use --mode details instead."
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

    if [[ "$MODE" == "overview" ]]; then
        if [[ -n "${FIELDS_OVERRIDE:-}" ]]; then
            log_warn "Ignoring --fields in overview mode"
        fi
    fi

    if [[ "$MODE" == "health" || "$MODE" == "problems" ]]; then
        if [[ -n "$HEALTH_ISSUE_FILTER" ]]; then
            SHOW_HEALTH_DETAILS=true
        fi

        if [[ -n "${FIELDS_OVERRIDE:-}" ]]; then
            log_warn "Ignoring --fields in ${MODE} mode"
        fi
    fi

    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid filter regex: $TARGET_FILTER"
    fi
}

# ------------------------------------------------------------------------------
# Function: load_json_selection
# Purpose.: Load selected target JSON payload from file
# Args....: $1 - path to JSON file
# Returns.: 0 on success, exits on error
# Output..: Normalized JSON object with .data array
# ------------------------------------------------------------------------------
load_json_selection() {
    local input_file="$1"

    if ! jq -e . "$input_file" > /dev/null 2>&1; then
        die "Invalid JSON in file: $input_file"
    fi

    if jq -e 'type == "array"' "$input_file" > /dev/null 2>&1; then
        jq '{data: .}' "$input_file"
        return 0
    fi

    if jq -e 'type == "object" and (.data | type == "array")' "$input_file" > /dev/null 2>&1; then
        jq '.' "$input_file"
        return 0
    fi

    die "Unsupported input JSON structure in $input_file. Expected array or object with .data array"
}

# ------------------------------------------------------------------------------
# Function: save_json_selection
# Purpose.: Persist selected target JSON payload to file
# Args....: $1 - JSON payload
#           $2 - output file path
# Returns.: 0 on success, exits on error
# Output..: Writes JSON file
# ------------------------------------------------------------------------------
save_json_selection() {
    local json_data="$1"
    local output_file="$2"
    local output_dir

    output_dir=$(dirname "$output_file")
    [[ "$output_dir" == "." ]] || mkdir -p "$output_dir"

    echo "$json_data" | jq '.' > "$output_file"
    log_info "Saved selected target JSON to: $output_file"
}

# ------------------------------------------------------------------------------
# Function: collect_selected_targets_json
# Purpose.: Resolve selected targets from OCI or input JSON
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: JSON object with .data array
# ------------------------------------------------------------------------------
collect_selected_targets_json() {
    local json_data
    local raw_json

    if [[ -n "$INPUT_JSON" ]]; then
        raw_json=$(load_json_selection "$INPUT_JSON") || die "Failed to load input JSON"
        REPORT_RAW_TARGETS=$(echo "$raw_json" | jq '.data | length')
        json_data="$raw_json"

        if [[ -n "$TARGET_FILTER" ]]; then
            json_data=$(apply_target_filter "$json_data") || die "Failed to apply target filter on input JSON"
        fi

        if [[ -n "$LIFECYCLE_STATE" ]]; then
            json_data=$(echo "$json_data" | jq --arg state "$LIFECYCLE_STATE" '.data = (.data | map(select((."lifecycle-state" // "") == $state)))')
        fi

        REPORT_SELECTED_TARGETS=$(echo "$json_data" | jq '.data | length')
        COLLECTED_JSON_DATA="$json_data"
        return 0
    fi

    if [[ "$MODE" == "report" ]]; then
        raw_json=$(ds_collect_targets "$COMPARTMENT" "$TARGETS" "" "") || return 1
        REPORT_RAW_TARGETS=$(echo "$raw_json" | jq '.data | length')

        json_data="$raw_json"
        if [[ -n "$LIFECYCLE_STATE" ]]; then
            json_data=$(echo "$json_data" | jq --arg state "$LIFECYCLE_STATE" '.data = (.data | map(select((."lifecycle-state" // "") == $state)))')
        fi
        if [[ -n "$TARGET_FILTER" ]]; then
            json_data=$(apply_target_filter "$json_data") || return 1
        fi

        REPORT_SELECTED_TARGETS=$(echo "$json_data" | jq '.data | length')
        COLLECTED_JSON_DATA="$json_data"
        return 0
    fi

    json_data=$(ds_collect_targets "$COMPARTMENT" "$TARGETS" "$LIFECYCLE_STATE" "$TARGET_FILTER") || return 1
    REPORT_RAW_TARGETS=$(echo "$json_data" | jq '.data | length')
    REPORT_SELECTED_TARGETS="$REPORT_RAW_TARGETS"
    COLLECTED_JSON_DATA="$json_data"
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
# Function: safe_div
# Purpose.: Safely divide two numeric values
# Args....: $1 - numerator
#           $2 - denominator
#           $3 - decimals (optional, default: 4)
# Returns.: 0
# Output..: decimal result, or 0 when denominator is 0
# ------------------------------------------------------------------------------
safe_div() {
    local numerator="${1:-0}"
    local denominator="${2:-0}"
    local decimals="${3:-4}"

    awk -v n="$numerator" -v d="$denominator" -v p="$decimals" 'BEGIN {
        if (d == 0) {
            printf "0"
        } else {
            fmt = "%.*f"
            printf fmt, p, (n / d)
        }
    }'
}

# ------------------------------------------------------------------------------
# Function: format_pct
# Purpose.: Format decimal ratio as percentage string
# Args....: $1 - ratio (0..1)
# Returns.: 0
# Output..: percentage with one decimal and % sign
# ------------------------------------------------------------------------------
format_pct() {
    local ratio="${1:-0}"
    awk -v r="$ratio" 'BEGIN { printf "%.1f%%", (r * 100) }'
}

# ------------------------------------------------------------------------------
# Function: format_human_time
# Purpose.: Convert ISO UTC timestamp to human-readable UTC string
# Args....: $1 - timestamp in ISO format (e.g. 2026-02-23T09:02:07Z)
# Returns.: 0
# Output..: formatted time (YYYY-MM-DD HH:MM:SS UTC) or original input
# ------------------------------------------------------------------------------
format_human_time() {
    local iso_time="${1:-}"

    if [[ -z "$iso_time" ]]; then
        echo "unknown"
        return 0
    fi

    if command -v date > /dev/null 2>&1; then
        if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_time" "+%Y-%m-%d %H:%M:%S UTC" > /dev/null 2>&1; then
            date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_time" "+%Y-%m-%d %H:%M:%S UTC"
            return 0
        fi
    fi

    echo "$iso_time"
}

# ------------------------------------------------------------------------------
# Function: shorten_list
# Purpose.: Shorten comma-separated list to max items with +N suffix
# Args....: $1 - comma-separated values
#           $2 - max items
# Returns.: 0
# Output..: shortened list string
# ------------------------------------------------------------------------------
shorten_list() {
    local values_csv="${1:-}"
    local max_items="${2:-10}"

    if [[ -z "$values_csv" ]]; then
        echo "-"
        return 0
    fi

    local -a values=()
    IFS=',' read -ra values <<< "$values_csv"

    local total=${#values[@]}
    if ((total <= max_items)); then
        echo "$values_csv"
        return 0
    fi

    local -a kept=()
    local idx
    for ((idx = 0; idx < max_items; idx++)); do
        kept+=("${values[$idx]}")
    done

    local kept_csv
    kept_csv=$(join_by "," "${kept[@]}")
    echo "${kept_csv} +$((total - max_items)) more"
}

# ------------------------------------------------------------------------------
# Function: load_last_report
# Purpose.: Load previous report snapshot if available
# Args....: $1 - state file path
# Returns.: 0
# Output..: JSON object to stdout (empty object if unavailable/invalid)
# ------------------------------------------------------------------------------
load_last_report() {
    local state_file="$1"

    if [[ ! -r "$state_file" ]]; then
        echo '{}'
        return 0
    fi

    if ! jq -e . "$state_file" > /dev/null 2>&1; then
        log_warn "Ignoring invalid previous report state: $state_file"
        echo '{}'
        return 0
    fi

    jq '.' "$state_file"
}

# ------------------------------------------------------------------------------
# Function: save_last_report
# Purpose.: Persist lightweight report snapshot for next delta calculation
# Args....: $1 - state file path
#           $2 - snapshot JSON payload
# Returns.: 0 on success, 1 on write error
# Output..: None
# ------------------------------------------------------------------------------
save_last_report() {
    local state_file="$1"
    local snapshot_json="$2"
    local state_dir

    state_dir=$(dirname "$state_file")
    mkdir -p "$state_dir"

    echo "$snapshot_json" | jq '.' > "$state_file"
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
# Function: health_issue_action
# Purpose.: Provide suggested action text for an issue code
# Args....: $1 - issue code
# Returns.: 0
# Output..: action text to stdout
# ------------------------------------------------------------------------------
health_issue_action() {
    local issue_code="$1"

    case "$issue_code" in
        TARGET_NEEDS_ATTENTION_ACCOUNT_LOCKED)
            echo "Unlock/reset account; update creds; refresh"
            ;;
        TARGET_NEEDS_ATTENTION_CREDENTIALS)
            echo "Reset/update DB creds; refresh target"
            ;;
        TARGET_NEEDS_ATTENTION_CONNECTIVITY)
            echo "Check connector/network/listener; refresh"
            ;;
        TARGET_NEEDS_ATTENTION_FETCH_DETAILS)
            echo "Validate connect details; refresh"
            ;;
        TARGET_NEEDS_ATTENTION_OTHER)
            echo "Review lifecycle-details; targeted checks"
            ;;
        SID_MISSING_ROOT)
            echo "Register/refresh missing CDB root"
            ;;
        SID_DUPLICATE_ROOT)
            echo "Review duplicate roots; keep one"
            ;;
        SID_ROOT_WITHOUT_PDB)
            echo "Verify/register missing PDB targets"
            ;;
        TARGET_INACTIVE)
            echo "Activate target if expected"
            ;;
        TARGET_UNEXPECTED_STATE)
            echo "Wait/retry; refresh after state stabilizes"
            ;;
        TARGET_NAMING_NONSTANDARD)
            echo "Adjust naming regex/standard"
            ;;
        *)
            echo "Review details and remediate"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: filter_health_issue_rows
# Purpose.: Filter health issue rows by issue code or label text
# Args....: $1 - TSV issue rows
#           $2 - issue selector (code or label text)
# Returns.: 0
# Output..: filtered TSV issue rows
# ------------------------------------------------------------------------------
filter_health_issue_rows() {
    local issue_rows="$1"
    local selector="$2"

    if [[ -z "$selector" ]]; then
        printf '%s' "$issue_rows"
        return 0
    fi

    local selector_lc
    selector_lc=$(printf '%s' "$selector" | tr '[:upper:]' '[:lower:]')

    local filtered_rows=""
    while IFS=$'\t' read -r issue_type severity cluster sid target state reason action; do
        [[ -z "$issue_type" ]] && continue

        local issue_lc issue_label issue_label_lc
        issue_lc=$(printf '%s' "$issue_type" | tr '[:upper:]' '[:lower:]')
        issue_label=$(health_issue_label "$issue_type")
        issue_label_lc=$(printf '%s' "$issue_label" | tr '[:upper:]' '[:lower:]')

        if [[ "$issue_lc" == "$selector_lc" || "$issue_label_lc" == "$selector_lc" || "$issue_label_lc" == *"$selector_lc"* ]]; then
            filtered_rows+="${issue_type}"$'\t'"${severity}"$'\t'"${cluster}"$'\t'"${sid}"$'\t'"${target}"$'\t'"${state}"$'\t'"${reason}"$'\t'"${action}"$'\n'
        fi
    done <<< "$issue_rows"

    filtered_rows="${filtered_rows%$'\n'}"
    printf '%s' "$filtered_rows"
}

# ------------------------------------------------------------------------------
# Function: filter_health_scope_rows
# Purpose.: Filter health issue rows by scope model
# Args....: $1 - TSV issue rows
#           $2 - scope (all|needs_attention)
# Returns.: 0
# Output..: filtered TSV issue rows
# ------------------------------------------------------------------------------
filter_health_scope_rows() {
    local issue_rows="$1"
    local scope="$2"

    if [[ "$scope" == "all" ]]; then
        printf '%s' "$issue_rows"
        return 0
    fi

    if [[ "$scope" == "needs_attention" ]]; then
        echo "$issue_rows" | awk -F '\t' '$1 ~ /^TARGET_NEEDS_ATTENTION/ || $1 == "TARGET_INACTIVE" || $1 == "TARGET_UNEXPECTED_STATE"'
        return 0
    fi

    printf '%s' "$issue_rows"
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

    issue_rows=$(filter_health_scope_rows "$issue_rows" "$HEALTH_SCOPE")

    if [[ -n "$HEALTH_ISSUE_FILTER" ]]; then
        issue_rows=$(filter_health_issue_rows "$issue_rows" "$HEALTH_ISSUE_FILTER")
        if [[ -z "$issue_rows" ]]; then
            log_warn "No health issues matched selector: ${HEALTH_ISSUE_FILTER}"
            case "$OUTPUT_FORMAT" in
                table)
                    printf "\nNo health issues matched selector: %s\n\n" "$HEALTH_ISSUE_FILTER"
                    ;;
                json)
                    echo '[]'
                    ;;
                csv)
                    if [[ "$SHOW_HEALTH_DETAILS" == "true" ]]; then
                        if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
                            echo "issue,severity,cluster,sid,target,state,reason,action"
                        else
                            echo "issue,severity,cluster,sid,target,state,reason"
                        fi
                    else
                        if [[ "$SHOW_HEALTH_ACTIONS" == "true" ]]; then
                            echo "issue,severity,count,sid_count,action"
                        else
                            echo "issue,severity,count,sid_count"
                        fi
                    fi
                    ;;
            esac
            return 0
        fi
    fi

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

    # Set column widths (display-name gets more space)
    for field in "${field_array[@]}"; do
        if [[ "$field" == "display-name" ]]; then
            field_widths+=(50)
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

                # Truncate long values
                local display_value="${value:0:$max_len}"
                [[ ${#value} -gt $max_len ]] && display_value="${display_value}.."
                printf "%-${width}s " "$display_value"
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
# Function: build_consolidated_report_json
# Purpose.: Build one-page high-level report payload
# Args....: $1 - selected target JSON object
# Returns.: 0 on success
# Output..: Consolidated report JSON object
# ------------------------------------------------------------------------------
build_consolidated_report_json() {
    local json_data="$1"
    local selected_count
    local lifecycle_counts_json
    local overview_rows
    local issue_rows
    local issue_analytics_json
    local issue_summary_json
    local needs_attention_breakdown_json
    local top_sids_json
    local top_sids_total=0
    local run_timestamp
    local run_hash
    local run_id
    local coverage_sid_cdb_ratio
    local coverage_avg_pdb_per_cdb
    local coverage_avg_targets_per_sid
    local sid_with_root_count=0

    selected_count=$(echo "$json_data" | jq '.data | length')
    REPORT_SELECTED_TARGETS="$selected_count"

    run_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if command -v shasum > /dev/null 2>&1; then
        run_hash=$(printf '%s' "$json_data" | shasum -a 1 | awk '{print substr($1,1,8)}')
    else
        run_hash=$(printf '%s' "$json_data" | openssl sha1 | awk '{print substr($NF,1,8)}')
    fi
    run_id="${run_timestamp}-${run_hash}"

    lifecycle_counts_json=$(echo "$json_data" | jq '
        .data
        | map(."lifecycle-state" // "UNKNOWN")
        | group_by(.)
        | map({state: .[0], count: length})
        | sort_by(-.count, .state)
    ')

    overview_rows=$(build_overview_rows "$json_data")
    issue_rows=$(evaluate_health_issues "$json_data")

    issue_analytics_json=$(jq -R -s '
        def sev_rank: if . == "HIGH" then 3 elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end;
        def map_category:
            if . == "TARGET_NEEDS_ATTENTION_ACCOUNT_LOCKED" or . == "TARGET_NEEDS_ATTENTION_CREDENTIALS" then "credential issue"
            elif . == "TARGET_NEEDS_ATTENTION_CONNECTIVITY" then "connectivity/timeout"
            else "other/unknown"
            end;
        (split("\n") | map(select(length > 0) | split("\t"))) as $rows
        | ($rows | map({type: .[0], severity: .[1], sid: .[3], action: .[7]})) as $issues
        | {
            issue_summary:
                ($issues
                 | group_by(.type)
                 | map({
                     issue: .[0].type,
                     severity: (map(.severity) | max_by(sev_rank)),
                     count: length,
                     sid_count: (map(.sid) | map(select(. != "-" and . != "")) | unique | length),
                     action: .[0].action
                   })
                 | sort_by(-(.severity | sev_rank), -.count, -.sid_count, .issue)),
            needs_attention_breakdown:
                ($issues
                 | map(select(.type | startswith("TARGET_NEEDS_ATTENTION")))
                 | map({category: (.type | map_category), sid: .sid})
                 | group_by(.category)
                 | map({
                     category: .[0].category,
                     count: length,
                     sid_count: (map(.sid) | map(select(. != "-" and . != "")) | unique | length),
                     sids: (map(.sid) | map(select(. != "-" and . != "")) | unique | sort)
                   })
                 | sort_by(-.count, .category)),
            top_sids:
                ($issues
                 | map({severity: .severity, sid: .sid})
                 | map(select(.sid != "-" and .sid != ""))
                 | group_by(.sid)
                 | map({
                     sid: .[0].sid,
                     total: length,
                     high: (map(select(.severity == "HIGH")) | length),
                     medium: (map(select(.severity == "MEDIUM")) | length),
                     low: (map(select(.severity == "LOW")) | length)
                   })
                 | sort_by(-.total, -.high, .sid)
                 | .[0:10]),
            top_sids_total:
                ($issues
                 | map(.sid)
                 | map(select(. != "-" and . != ""))
                 | unique
                 | length),
            total_issue_count: ($rows | length),
            naming_nonstandard_count: ($rows | map(select(.[0] == "TARGET_NAMING_NONSTANDARD")) | length)
          }
    ' <<< "$issue_rows")

    issue_summary_json=$(jq -c '.issue_summary' <<< "$issue_analytics_json")
    needs_attention_breakdown_json=$(jq -c '.needs_attention_breakdown' <<< "$issue_analytics_json")
    top_sids_json=$(jq -c '.top_sids' <<< "$issue_analytics_json")
    top_sids_total=$(jq -r '.top_sids_total' <<< "$issue_analytics_json")

    local total_clusters=0
    local total_sids=0
    local total_cdbroots=0
    local total_pdbs=0
    local total_targets=0
    local -A seen_clusters=()

    while IFS=$'\t' read -r cluster _sid cdb_count pdb_count target_count _members _status; do
        [[ -z "$cluster" ]] && continue
        total_sids=$((total_sids + 1))
        if ((cdb_count > 0)); then
            sid_with_root_count=$((sid_with_root_count + 1))
        fi
        total_cdbroots=$((total_cdbroots + cdb_count))
        total_pdbs=$((total_pdbs + pdb_count))
        total_targets=$((total_targets + target_count))
        seen_clusters["$cluster"]=1
    done <<< "$overview_rows"
    total_clusters=${#seen_clusters[@]}

    local total_issue_count=0
    total_issue_count=$(jq -r '.total_issue_count' <<< "$issue_analytics_json")

    local naming_nonstandard_count=0
    naming_nonstandard_count=$(jq -r '.naming_nonstandard_count' <<< "$issue_analytics_json")

    coverage_sid_cdb_ratio=$(safe_div "$total_cdbroots" "$total_sids" 4)
    coverage_avg_pdb_per_cdb=$(safe_div "$total_pdbs" "$total_cdbroots" 4)
    coverage_avg_targets_per_sid=$(safe_div "$selected_count" "$total_sids" 4)

    jq -n \
        --arg run_id "$run_id" \
        --arg run_timestamp "$run_timestamp" \
        --arg scope_type "${REPORT_SCOPE_TYPE:-unknown}" \
        --arg scope_label "${REPORT_SCOPE_LABEL:-}" \
        --arg compartment_name "${REPORT_COMPARTMENT_NAME:-}" \
        --arg compartment_ocid "${REPORT_COMPARTMENT_OCID:-}" \
        --arg filters "${REPORT_FILTERS:-none}" \
        --argjson raw_targets "$REPORT_RAW_TARGETS" \
        --argjson selected_targets "$selected_count" \
        --argjson lifecycle_counts "$lifecycle_counts_json" \
        --argjson total_clusters "$total_clusters" \
        --argjson total_sids "$total_sids" \
        --argjson sid_with_root_count "$sid_with_root_count" \
        --argjson total_cdbroots "$total_cdbroots" \
        --argjson total_pdbs "$total_pdbs" \
        --argjson total_targets "$total_targets" \
        --argjson parse_skipped "$OVERVIEW_PARSE_SKIPPED" \
        --argjson total_issues "$total_issue_count" \
        --argjson naming_nonstandard "$naming_nonstandard_count" \
        --argjson coverage_sid_cdb_ratio "$coverage_sid_cdb_ratio" \
        --argjson coverage_avg_pdb_per_cdb "$coverage_avg_pdb_per_cdb" \
        --argjson coverage_avg_targets_per_sid "$coverage_avg_targets_per_sid" \
        --argjson issues "$issue_summary_json" \
        --argjson needs_attention_breakdown "$needs_attention_breakdown_json" \
        --argjson top_affected_sids "$top_sids_json" \
        --argjson top_affected_sids_total "$top_sids_total" \
        '{
            generated_at: (now | todateiso8601),
            run: {
                id: $run_id,
                timestamp: $run_timestamp
            },
            scope: {
                type: $scope_type,
                label: $scope_label,
                compartment_name: $compartment_name,
                compartment_ocid: $compartment_ocid,
                filters: $filters,
                raw_targets: $raw_targets,
                selected_targets: $selected_targets
            },
            targets: {
                selected: $selected_targets,
                lifecycle: $lifecycle_counts
            },
            landscape: {
                clusters: $total_clusters,
                sids: $total_sids,
                sids_with_root: $sid_with_root_count,
                cdb_roots: $total_cdbroots,
                pdbs: $total_pdbs,
                targets: $total_targets
            },
            issues: {
                total: $total_issues,
                summary: $issues
            },
            coverage_metrics: {
                sid_to_cdb_ratio: $coverage_sid_cdb_ratio,
                avg_pdbs_per_cdb: $coverage_avg_pdb_per_cdb,
                avg_targets_per_sid: $coverage_avg_targets_per_sid
            },
            needs_attention: {
                total: ([ $lifecycle_counts[]? | select(.state == "NEEDS_ATTENTION") | .count ] | add // 0),
                breakdown: $needs_attention_breakdown
            },
            top_affected_sids_total: $top_affected_sids_total,
            top_affected_sids: $top_affected_sids,
            warnings: {
                overview_parse_skipped: $parse_skipped,
                naming_nonstandard: $naming_nonstandard
            }
        }'
}

# ------------------------------------------------------------------------------
# Function: show_report_table
# Purpose.: Display consolidated high-level report as one-page table
# Args....: $1 - consolidated report JSON
# Returns.: 0
# Output..: Human-readable report
# ------------------------------------------------------------------------------
show_report_table() {
    local report_json="$1"
    local report_meta_row
    local total_sids
    local total_sids_int
    local sid_cdb_ratio
    local sid_cdb_pct
    local avg_pdb_per_cdb
    local avg_targets_per_sid
    local needs_attention_total
    local label_width=11
    local run_id
    local run_timestamp
    local scope_type
    local context_label
    local context_ocid
    local compartment_name
    local compartment_ocid
    local filters
    local raw_targets
    local selected_scope_targets
    local selected_targets
    local total_clusters
    local total_cdb_roots
    local total_pdbs
    local sids_with_root
    local context_display
    local total_issues
    local warning_parse_skipped
    local warning_naming_nonstandard
    local shown_top_sids
    local total_top_sids

    report_meta_row=$(jq -r '
        [
            .run.id,
            .run.timestamp,
            .scope.type,
            (.scope.label // "-"),
            (if .scope.compartment_ocid == null or .scope.compartment_ocid == "" then "" else .scope.compartment_ocid end),
            (if .scope.compartment_name == null or .scope.compartment_name == "" then "-" else .scope.compartment_name end),
            (if .scope.compartment_ocid == null or .scope.compartment_ocid == "" then "-" else .scope.compartment_ocid end),
            (.scope.filters // "none"),
            (.scope.raw_targets | tostring),
            (.scope.selected_targets | tostring),
            (.targets.selected | tostring),
            (.landscape.clusters | tostring),
            (.landscape.sids | tostring),
            (.landscape.sids_with_root | tostring),
            (.landscape.cdb_roots | tostring),
            (.landscape.pdbs | tostring),
            (.issues.total | tostring),
            (.coverage_metrics.sid_to_cdb_ratio | tostring),
            (.coverage_metrics.avg_pdbs_per_cdb | tostring),
            (.coverage_metrics.avg_targets_per_sid | tostring),
            (.needs_attention.total | tostring),
            (.warnings.overview_parse_skipped | tostring),
            (.warnings.naming_nonstandard | tostring),
            (.top_affected_sids | length | tostring),
            (.top_affected_sids_total | tostring)
        ] | join("\u001f")
    ' <<< "$report_json")

    IFS=$'\x1f' read -r run_id run_timestamp scope_type context_label context_ocid compartment_name compartment_ocid filters raw_targets selected_scope_targets selected_targets total_clusters total_sids sids_with_root total_cdb_roots total_pdbs total_issues sid_cdb_ratio avg_pdb_per_cdb avg_targets_per_sid needs_attention_total warning_parse_skipped warning_naming_nonstandard shown_top_sids total_top_sids <<< "$report_meta_row"

    total_sids_int=${total_sids:-0}
    context_display="$context_label"
    if [[ "$context_label" == "DS_ROOT_COMP" && -n "$context_ocid" ]]; then
        context_display="${context_label} (${context_ocid})"
    fi

    printf "\nData Safe Target Report (High-Level)\n"
    printf "%-*s : %s\n" "$label_width" "Run ID" "$run_id"
    printf "%-*s : %s\n" "$label_width" "Generated" "$run_timestamp"
    printf "%-*s : %s\n" "$label_width" "Scope" "$scope_type"
    printf "%-*s : %s\n" "$label_width" "Context" "$context_display"
    printf "%-*s : %s (%s)\n" "$label_width" "Compartment" "$compartment_name" "$compartment_ocid"
    printf "%-*s : %s\n" "$label_width" "Filters" "$filters"
    printf "%-*s : raw=%s selected=%s\n" "$label_width" "Targets" \
        "$raw_targets" \
        "$selected_scope_targets"
    printf "\n"

    printf "%-28s %10d\n" "Selected targets" "$selected_targets"
    printf "%-28s %10d\n" "Total clusters" "$total_clusters"
    printf "%-28s %10d\n" "Total Oracle SIDs" "$total_sids"
    printf "%-28s %10d\n" "Total CDB roots" "$total_cdb_roots"
    printf "%-28s %10d\n" "Total PDBs" "$total_pdbs"
    printf "%-28s %10d\n" "Total issues" "$total_issues"
    printf "\n"

    sid_cdb_pct=$(format_pct "$sid_cdb_ratio")

    printf "Coverage Metrics:\n"
    printf "  SID->CDB coverage : %s/%s (%s)\n" "$sids_with_root" "$total_sids" "$sid_cdb_pct"
    printf "  CDB root targets : %s\n" "$total_cdb_roots"
    printf "  Avg PDBs per CDB : %.2f\n" "$avg_pdb_per_cdb"
    printf "  Avg targets/SID  : %.2f\n" "$avg_targets_per_sid"
    printf "\n"

    printf "Lifecycle distribution:\n"
    echo "$report_json" | jq -r '.targets.lifecycle[] | [.state, (.count|tostring)] | @tsv' \
        | while IFS=$'\t' read -r lifecycle_state lifecycle_count; do
            printf "  - %-19s : %s\n" "$lifecycle_state" "$lifecycle_count"
        done
    if [[ "$needs_attention_total" -gt 0 ]]; then
        printf "\nNEEDS_ATTENTION breakdown (total=%s):\n" "$needs_attention_total"
        printf "%-23s %7s %7s %s\n" "Category" "Count" "SIDs" "Sample SIDs"
        printf "%-23s %7s %7s %s\n" "-----------------------" "-------" "-------" "------------------------------"
        echo "$report_json" | jq -r '.needs_attention.breakdown[] | [.category, (.count|tostring), (.sid_count|tostring), (.sids|join(","))] | @tsv' \
            | while IFS=$'\t' read -r category count sid_count sid_csv; do
                local sid_display
                sid_display=$(shorten_list "$sid_csv" 10)
                printf "%-23s %7d %7d %s\n" "$category" "$count" "$sid_count" "$sid_display"
            done
    else
        printf "\nNEEDS_ATTENTION breakdown: none\n"
    fi
    printf "\n"

    printf "Warnings:\n"
    printf "  - Overview parse skipped: %s\n" "$warning_parse_skipped"
    printf "  - Naming non-standard:    %s\n" "$warning_naming_nonstandard"
    printf "\n"

    if [[ "$total_issues" -gt 0 ]]; then
        printf "Issue summary (severity/count/SIDs):\n"
        printf "%-44s %-8s %8s %8s %7s %s\n" "Issue" "Severity" "Count" "SIDs" "SID %" "Suggested Action"
        printf "%-44s %-8s %8s %8s %7s %s\n" "--------------------------------------------" "--------" "--------" "--------" "-------" "------------------------------"
        echo "$report_json" | jq -r '.issues.summary[] | [.issue, .severity, (.count|tostring), (.sid_count|tostring), (.action // "")] | @tsv' \
            | while IFS=$'\t' read -r issue_type severity count sid_count action; do
                local issue_display
                local sid_ratio
                local sid_pct
                local action_display
                issue_display="$(health_issue_label "$issue_type")"
                if [[ ${#issue_display} -gt 44 ]]; then
                    issue_display="${issue_display:0:41}..."
                fi
                action_display="$action"
                if [[ -z "$action_display" ]]; then
                    action_display="$(health_issue_action "$issue_type")"
                fi

                sid_ratio=$(safe_div "$sid_count" "$total_sids_int" 4)
                sid_pct=$(format_pct "$sid_ratio")
                printf "%-44s %-8s %8d %8d %7s %s\n" "$issue_display" "$severity" "$count" "$sid_count" "$sid_pct" "$action_display"
            done
    else
        printf "Issue summary: none\n"
    fi
    printf "\n"

    if [[ "$total_top_sids" -gt 0 ]]; then
        printf "Top affected SIDs (top 10 by issue count):\n"
        printf "  showing %d of %d affected SIDs\n" "$shown_top_sids" "$total_top_sids"
        echo "$report_json" | jq -r '.top_affected_sids[] | "  - \(.sid): total=\(.total) (HIGH:\(.high) MEDIUM:\(.medium) LOW:\(.low))"'
    else
        printf "Top affected SIDs: none\n"
    fi
    printf "\n"

    local base_state_dir
    local state_file
    local current_snapshot
    local previous_snapshot
    local previous_run_timestamp
    base_state_dir="${ODB_DATASAFE_BASE:-${SCRIPT_DIR}/..}"
    state_file="${base_state_dir}/log/ds_target_last_report.json"

    current_snapshot=$(jq -n \
        --arg timestamp "$(echo "$report_json" | jq -r '.run.timestamp')" \
        --arg scope_key "${REPORT_SCOPE_KEY}" \
        --argjson selected_targets "$(echo "$report_json" | jq '.targets.selected')" \
        --argjson total_issues "$(echo "$report_json" | jq '.issues.total')" \
        --argjson high_issues "$(echo "$report_json" | jq '[.issues.summary[]? | select(.severity == "HIGH") | .count] | add // 0')" \
        --argjson medium_issues "$(echo "$report_json" | jq '[.issues.summary[]? | select(.severity == "MEDIUM") | .count] | add // 0')" \
        --argjson low_issues "$(echo "$report_json" | jq '[.issues.summary[]? | select(.severity == "LOW") | .count] | add // 0')" \
        --argjson needs_attention "$(echo "$report_json" | jq '.needs_attention.total')" \
        '{
            timestamp: $timestamp,
            scope_key: $scope_key,
            selected_targets: $selected_targets,
            total_issues: $total_issues,
            high_issues: $high_issues,
            medium_issues: $medium_issues,
            low_issues: $low_issues,
            needs_attention: $needs_attention
        }')

    previous_snapshot=$(load_last_report "$state_file")
    previous_run_timestamp=$(echo "$previous_snapshot" | jq -r '.timestamp // "unknown"')

    printf "Delta vs previous run:\n"
    if [[ "$(echo "$previous_snapshot" | jq 'length')" -eq 0 ]]; then
        printf "  Previous run   : n/a\n"
        printf "  selected_targets : n/a\n"
        printf "  total_issues     : n/a\n"
        printf "  high_issues      : n/a\n"
        printf "  medium_issues    : n/a\n"
        printf "  low_issues       : n/a\n"
        printf "  needs_attention  : n/a\n"
    else
        if [[ "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].scope_key == .[1].scope_key')" != "true" ]]; then
            printf "  Previous run   : %s (different scope)\n" "$(format_human_time "$previous_run_timestamp")"
            printf "  delta values   : n/a for different scope\n"
        else
            printf "  Previous run   : %s\n" "$(format_human_time "$previous_run_timestamp")"
            printf "  selected_targets : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.selected_targets')" \
                "$(echo "$current_snapshot" | jq -r '.selected_targets')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].selected_targets - .[1].selected_targets')"
            printf "  total_issues     : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.total_issues')" \
                "$(echo "$current_snapshot" | jq -r '.total_issues')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].total_issues - .[1].total_issues')"
            printf "  high_issues      : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.high_issues')" \
                "$(echo "$current_snapshot" | jq -r '.high_issues')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].high_issues - .[1].high_issues')"
            printf "  medium_issues    : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.medium_issues')" \
                "$(echo "$current_snapshot" | jq -r '.medium_issues')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].medium_issues - .[1].medium_issues')"
            printf "  low_issues       : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.low_issues')" \
                "$(echo "$current_snapshot" | jq -r '.low_issues')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].low_issues - .[1].low_issues')"
            printf "  needs_attention  : %7d -> %7d (delta %+7d)\n" \
                "$(echo "$previous_snapshot" | jq -r '.needs_attention')" \
                "$(echo "$current_snapshot" | jq -r '.needs_attention')" \
                "$(echo "$current_snapshot $previous_snapshot" | jq -s '.[0].needs_attention - .[1].needs_attention')"
        fi
    fi
    printf "\n"

    if ! save_last_report "$state_file" "$current_snapshot"; then
        log_warn "Could not save report state file: $state_file"
    fi
}

# ------------------------------------------------------------------------------
# Function: show_report_csv
# Purpose.: Display consolidated report as flattened CSV
# Args....: $1 - consolidated report JSON
# Returns.: 0
# Output..: CSV rows with section,key,value,extra
# ------------------------------------------------------------------------------
show_report_csv() {
    local report_json="$1"

    echo "section,key,value,extra"

    echo "$report_json" | jq -r '
        [
            ["targets","selected",(.targets.selected|tostring),""],
            ["landscape","clusters",(.landscape.clusters|tostring),""],
            ["landscape","sids",(.landscape.sids|tostring),""],
            ["landscape","cdb_roots",(.landscape.cdb_roots|tostring),""],
            ["landscape","pdbs",(.landscape.pdbs|tostring),""],
            ["issues","total",(.issues.total|tostring),""],
            ["warnings","overview_parse_skipped",(.warnings.overview_parse_skipped|tostring),""],
            ["warnings","naming_nonstandard",(.warnings.naming_nonstandard|tostring),""]
        ]
        | .[]
        | @csv
    '

    echo "$report_json" | jq -r '.targets.lifecycle[] | ["lifecycle", .state, (.count|tostring), ""] | @csv'
    echo "$report_json" | jq -r '.issues.summary[] | ["issue", .issue, (.count|tostring), .severity] | @csv'
}

# ------------------------------------------------------------------------------
# Function: show_report
# Purpose.: Render consolidated report in requested format
# Args....: $1 - selected target JSON object
# Returns.: 0
# Output..: report output
# ------------------------------------------------------------------------------
show_report() {
    local json_data="$1"
    local report_json

    report_json=$(build_consolidated_report_json "$json_data")

    case "$OUTPUT_FORMAT" in
        table)
            show_report_table "$report_json"
            ;;
        json)
            echo "$report_json" | jq '.'
            ;;
        csv)
            show_report_csv "$report_json"
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

    if [[ -n "$INPUT_JSON" ]]; then
        log_info "Loading selected targets from JSON payload"
    elif [[ -n "$TARGETS" ]]; then
        log_info "Fetching details for specific targets..."
    else
        log_info "Listing targets in compartment hierarchy"
    fi

    collect_selected_targets_json || die "Failed to collect targets"
    json_data="$COLLECTED_JSON_DATA"

    if [[ -n "$SAVE_JSON" ]]; then
        save_json_selection "$json_data" "$SAVE_JSON"
    fi

    if [[ -n "$TARGET_FILTER" ]]; then
        local filtered_count
        filtered_count=$(echo "$json_data" | jq '.data | length')
        if [[ "$filtered_count" -eq 0 ]]; then
            log_info "No targets matched filter regex: $TARGET_FILTER"
        fi
    fi

    # Display results based on mode
    case "$MODE" in
        report)
            show_report "$json_data"
            ;;
        health | problems)
            show_health "$json_data"
            ;;
        count)
            show_count_summary "$json_data"
            ;;
        overview)
            show_overview "$json_data"
            ;;
        details)
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
            ;;
    esac
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
