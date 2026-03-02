#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: ds_target_audit_trail.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.03.02
# Version....: v0.17.4
# Purpose....: Start Oracle Data Safe audit trails for target databases.
#              Supports single/multiple targets by name/OCID, or compartment scan.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2> /dev/null | awk '{print $2}' | tr -d '\n' || echo '0.17.4')"
readonly SCRIPT_VERSION

# Defaults
: "${COMPARTMENT:=}"
: "${TARGETS:=}"
: "${SELECT_ALL:=false}"
: "${TARGET_FILTER:=}"
: "${LIFECYCLE:=ACTIVE}"
: "${START_TIME:=now}"
: "${AUTO_PURGE:=true}"
: "${INPUT_JSON:=}"         # --input-json: read targets from local JSON file
: "${SAVE_JSON:=}"          # --save-json: save selected target JSON payload
: "${LIST_MODE:=false}"     # --list: show audit trail status instead of starting
: "${OUTPUT_FORMAT:=table}" # -f/--format: output format for --list (table|json|csv)
# shellcheck disable=SC2034 # consumed by parse_common_opts in common.sh
SHOW_USAGE_ON_EMPTY_ARGS=true

# Runtime globals
RESOLVED_TARGETS=()
TARGETS_PAYLOAD_JSON=""  # Cached by resolve_targets(); reused by list_audit_trails()
started_count=0
failed_count=0

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
    Start or list Data Safe audit trails for target database(s). Supports single/
    multiple targets by name/OCID, compartment scan, or reading from a saved JSON.

Options:
  Common:
    -h, --help                      Show this help message
    -V, --version                   Show version
    -v, --verbose                   Enable verbose output
    -d, --debug                     Enable debug output
        --log-file FILE             Log to file

  OCI:
        --oci-profile PROFILE       OCI CLI profile (default: ${OCI_CLI_PROFILE:-DEFAULT})
        --oci-region REGION         OCI region
        --oci-config FILE           OCI config file

  Target Selection:
    -T, --targets LIST              Comma-separated target names/OCIDs
    -c, --compartment COMP          Compartment OCID or name (default: DS_ROOT_COMP)
    -A, --all                       Select all targets from DS_ROOT_COMP (requires DS_ROOT_COMP)
    -r, --filter REGEX              Filter target names by regex (substring match)
    -L, --lifecycle STATES          Lifecycle state filter (default: ACTIVE)
                                    Use comma-separated values: ACTIVE,NEEDS_ATTENTION
        --input-json FILE           Read targets from local JSON (from ds_target_list.sh --save-json)
        --save-json FILE            Save selected target JSON payload to file

  Action:
    -l, --list                      List audit trail lifecycle states (read-only)
    -n, --dry-run                   Show plan without starting trails (start mode only)

  Audit Configuration (start mode only):
        --start-time TIME           Collection start time (RFC3339 or 'now', default: now)
        --auto-purge true|false     Enable auto-purge on the audit trail (default: true)

  Output (list mode only):
    -f, --format FMT                Output format: table|json|csv (default: table)

Examples:
  # Start audit trail for specific target
  ${SCRIPT_NAME} -T my-target

  # Start trails for all ACTIVE targets in compartment
  ${SCRIPT_NAME} -c my-compartment -L ACTIVE

  # Multiple targets (dry-run)
  ${SCRIPT_NAME} -T target1,target2 --dry-run

  # List audit trail states for all targets in DS_ROOT_COMP
  ${SCRIPT_NAME} --list --all

  # List trail states from saved target JSON (avoids re-fetching targets from OCI)
  ${SCRIPT_NAME} --list --input-json ./targets.json

  # List trail states filtered by name, as CSV
  ${SCRIPT_NAME} --list --all --filter prod -f csv

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

    local -a remaining=()
    set -- "${ARGS[@]-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -T | --targets)
                need_val "$1" "${2:-}"
                TARGETS="$2"
                shift 2
                ;;
            -c | --compartment)
                need_val "$1" "${2:-}"
                COMPARTMENT="$2"
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
                LIFECYCLE="$2"
                shift 2
                ;;
            --start-time)
                need_val "$1" "${2:-}"
                START_TIME="$2"
                shift 2
                ;;
            --auto-purge)
                need_val "$1" "${2:-}"
                AUTO_PURGE="$2"
                shift 2
                ;;
            -l | --list)
                LIST_MODE=true
                shift
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
            -f | --format)
                need_val "$1" "${2:-}"
                OUTPUT_FORMAT="$2"
                shift 2
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

    # Handle positional arguments as additional targets
    if [[ ${#remaining[@]} -gt 0 ]]; then
        if [[ -z "$TARGETS" ]]; then
            TARGETS="${remaining[*]}"
        else
            TARGETS="${TARGETS},${remaining[*]}"
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

    require_oci_cli

    # Validate --input-json file is readable if provided
    if [[ -n "$INPUT_JSON" ]]; then
        [[ -r "$INPUT_JSON" ]] || die "Input JSON file not found or not readable: $INPUT_JSON"
    fi

    # Resolve --all to DS_ROOT_COMP (errors if combined with -c or -T)
    COMPARTMENT=$(ds_resolve_all_targets_scope "$SELECT_ALL" "$COMPARTMENT" "$TARGETS") \
        || die "Invalid --all usage. --all requires DS_ROOT_COMP and cannot be combined with -c/--compartment or -T/--targets"

    # If no explicit scope and no --input-json, fall back to DS_ROOT_COMP
    if [[ -z "$TARGETS" && -z "$COMPARTMENT" && -z "$INPUT_JSON" ]]; then
        COMPARTMENT=$(resolve_compartment_for_operation "") \
            || die "Specify -T/--targets, -c/--compartment, -A/--all, set DS_ROOT_COMP, or use --input-json"
        log_info "No compartment specified, using DS_ROOT_COMP: $COMPARTMENT"
    fi

    # Validate filter regex
    if ! ds_validate_target_filter_regex "$TARGET_FILTER"; then
        die "Invalid --filter regex: $TARGET_FILTER"
    fi

    if [[ "${LIST_MODE}" == "true" ]]; then
        log_info "Audit trail list mode"
    else
        # Validate boolean flag (start mode only)
        case "${AUTO_PURGE,,}" in
            true | false) ;;
            *) die "Invalid --auto-purge value: $AUTO_PURGE. Use: true or false" ;;
        esac
        log_info "Audit trail configuration:"
        log_info "  Start time: $START_TIME"
        log_info "  Auto-purge: $AUTO_PURGE"
    fi
}

# ------------------------------------------------------------------------------
# Function: resolve_targets
# Purpose.: Resolve target names/OCIDs to list of target OCIDs
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Populates RESOLVED_TARGETS array
# ------------------------------------------------------------------------------
resolve_targets() {
    log_debug "Resolving targets..."

    local targets_json
    targets_json=$(ds_collect_targets_source \
        "$COMPARTMENT" "$TARGETS" "$LIFECYCLE" "$TARGET_FILTER" \
        "$INPUT_JSON" "$SAVE_JSON") || return 1
    TARGETS_PAYLOAD_JSON="$targets_json"

    while IFS= read -r target_id; do
        [[ -n "$target_id" ]] && RESOLVED_TARGETS+=("$target_id")
    done < <(jq -r '.data[].id // empty' <<< "$targets_json")

    log_info "Found ${#RESOLVED_TARGETS[@]} target(s) for audit trail operation"
    return 0
}

# ------------------------------------------------------------------------------
# Function: list_audit_trails
# Purpose.: List audit trail lifecycle states for resolved targets
# Args....: None
# Returns.: 0 on success
# Output..: Table/JSON/CSV of target name, trail state, and advisory note
# Notes...: Extracts compartment-id from TARGETS_PAYLOAD_JSON to avoid an
#           extra target-database get call; falls back to oci_exec_ro when the
#           cached payload lacks compartment-id (e.g. explicit OCID targets).
# ------------------------------------------------------------------------------
list_audit_trails() {
    log_info "Listing audit trail states for ${#RESOLVED_TARGETS[@]} target(s)..."

    local -a rows=()

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        log_debug "  Querying: $target_ocid"

        # Extract name + compartment from cached payload (avoids an extra OCI call)
        local target_name target_compartment
        target_name=$(jq -r --arg id "$target_ocid" \
            '.data[] | select(.id == $id) | ."display-name" // empty' \
            <<< "$TARGETS_PAYLOAD_JSON")
        target_compartment=$(jq -r --arg id "$target_ocid" \
            '.data[] | select(.id == $id) | ."compartment-id" // empty' \
            <<< "$TARGETS_PAYLOAD_JSON")

        # Fall back to target-database get if compartment-id is missing in payload
        if [[ -z "$target_compartment" ]]; then
            local tgt_json
            tgt_json=$(oci_exec_ro data-safe target-database get \
                --target-database-id "$target_ocid" 2> /dev/null) || tgt_json="{}"
            [[ -z "$target_name" ]] && \
                target_name=$(jq -r '.data."display-name" // empty' <<< "$tgt_json")
            target_compartment=$(jq -r '.data."compartment-id" // empty' <<< "$tgt_json")
        fi
        [[ -z "$target_name" ]] && target_name="$target_ocid"
        [[ -z "$target_compartment" ]] && target_compartment="${COMPARTMENT:-${DS_ROOT_COMP:-}}"

        # Query audit trail state for this target
        local trails_json trail_state note
        trails_json=$(oci_exec_ro data-safe audit-trail list \
            --compartment-id "$target_compartment" \
            --target-id "$target_ocid" \
            --all 2> /dev/null) || trails_json='{"data":{"items":[]}}'

        trail_state=$(printf '%s' "$trails_json" | \
            jq -r '(.data.items // .data)[]?."lifecycle-state" // empty' | head -n1)

        if [[ -z "$trail_state" ]]; then
            trail_state="(no trail)"
            note="missing"
        else
            case "${trail_state^^}" in
                COLLECTING)               note="ok"               ;;
                STARTING | RESUMING)      note="starting"         ;;
                STOPPED)                  note="needs restart"    ;;
                INACTIVE)                 note="inactive"         ;;
                NEEDS_ATTENTION | FAILED) note="needs attention"  ;;
                DELETING | DELETED)       note="deleted"          ;;
                *)                        note=""                 ;;
            esac
        fi

        rows+=("${target_name}|${target_ocid}|${trail_state}|${note}")
    done

    # Render output in the requested format
    case "${OUTPUT_FORMAT,,}" in
        json)
            printf '[\n'
            local sep=""
            local name ocid state nte
            for row in "${rows[@]}"; do
                IFS='|' read -r name ocid state nte <<< "$row"
                printf '%s  {"target":"%s","target-id":"%s","trail-state":"%s","note":"%s"}\n' \
                    "$sep" "$name" "$ocid" "$state" "$nte"
                sep=","
            done
            printf ']\n'
            ;;
        csv)
            printf 'target,target-id,trail-state,note\n'
            local name ocid state nte
            for row in "${rows[@]}"; do
                IFS='|' read -r name ocid state nte <<< "$row"
                printf '%s,%s,%s,%s\n' "$name" "$ocid" "$state" "$nte"
            done
            ;;
        *)
            # shellcheck disable=SC2183  # printf repeating format is intentional
            printf '%-44s %-16s %s\n' "TARGET" "TRAIL STATE" "NOTE"
            printf '%-44s %-16s %s\n' \
                "$(printf '%0.s-' {1..44})" \
                "$(printf '%0.s-' {1..16})" \
                "$(printf '%0.s-' {1..20})"
            local name ocid state nte
            for row in "${rows[@]}"; do
                IFS='|' read -r name ocid state nte <<< "$row"
                printf '%-44s %-16s %s\n' "$name" "$state" "$nte"
            done
            ;;
    esac

    return 0
}

# ------------------------------------------------------------------------------
# Function: start_audit_trails
# Purpose.: Start audit trails for resolved targets
# Args....: None
# Returns.: 0 on partial/full success, 1 on all failures
# Output..: Log messages and error counters
# Notes...: Audit trails are started per-trail (list trails for target, then
#           start each by its audit-trail OCID). Valid start parameters:
#           --audit-collection-start-time, --is-auto-purge-enabled.
# ------------------------------------------------------------------------------
start_audit_trails() {
    log_info "Starting audit trails for targets..."

    started_count=0
    failed_count=0

    # Resolve 'now' to a proper RFC3339 UTC timestamp required by OCI CLI
    local collection_start_time
    if [[ "${START_TIME}" == "now" ]]; then
        collection_start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        collection_start_time="${START_TIME}"
    fi
    log_debug "  Collection start time: ${collection_start_time}"

    for target_ocid in "${RESOLVED_TARGETS[@]}"; do
        log_debug "  Processing: $target_ocid"

        # Fetch target details (name + compartment-id) for logging and audit-trail list
        local target_json target_name target_compartment
        target_json=$(oci_exec_ro data-safe target-database get \
            --target-database-id "$target_ocid" 2> /dev/null) || target_json="{}"
        target_name=$(jq -r '.data."display-name" // empty' <<< "$target_json")
        [[ -z "$target_name" ]] && target_name="$target_ocid"
        target_compartment=$(jq -r '.data."compartment-id" // empty' <<< "$target_json")
        [[ -z "$target_compartment" ]] && target_compartment="${COMPARTMENT:-${DS_ROOT_COMP:-}}"

        # List audit trails for this target (requires --compartment-id)
        local trails_json
        trails_json=$(oci_exec_ro data-safe audit-trail list \
            --compartment-id "$target_compartment" \
            --target-id "$target_ocid" \
            --all) || {
            log_error "Failed to list audit trails for: $target_name"
            failed_count=$((failed_count + 1))
            continue
        }
        # Extract id + lifecycle-state as TSV for each trail
        local trail_info
        trail_info=$(echo "$trails_json" | jq -r '(.data.items // .data)[]? | [.id, (."lifecycle-state" // "UNKNOWN")] | @tsv')

        if [[ -z "$trail_info" ]]; then
            log_warn "No audit trails found for: $target_name — skipping"
            started_count=$((started_count + 1))
            continue
        fi

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would start audit trail(s) for: $target_name (${target_ocid})"
            started_count=$((started_count + 1))
            continue
        fi

        # Start each audit trail by its OCID; skip already-running trails
        local trail_ok=0 trail_fail=0 trail_skip=0
        while IFS=$'\t' read -r trail_ocid trail_state; do
            [[ -z "$trail_ocid" ]] && continue
            case "${trail_state^^}" in
                COLLECTING | STARTING | RESUMING)
                    log_info "Audit trail already ${trail_state} for: $target_name — skipping"
                    trail_skip=$((trail_skip + 1))
                    continue
                    ;;
            esac
            if oci_exec data-safe audit-trail start \
                --audit-trail-id "$trail_ocid" \
                --audit-collection-start-time "$collection_start_time" \
                --is-auto-purge-enabled "$AUTO_PURGE" > /dev/null; then
                trail_ok=$((trail_ok + 1))
            else
                # Re-check state: if the trail is now running it was already started
                local post_state
                post_state=$(oci_exec_ro data-safe audit-trail get \
                    --audit-trail-id "$trail_ocid" \
                    --query 'data."lifecycle-state"' \
                    --raw-output 2> /dev/null || echo "UNKNOWN")
                case "${post_state^^}" in
                    COLLECTING | STARTING | RESUMING)
                        log_info "Audit trail already ${post_state} for: $target_name — skipping"
                        trail_skip=$((trail_skip + 1))
                        ;;
                    *)
                        log_error "Failed to start audit trail $trail_ocid for: $target_name (state: ${post_state})"
                        trail_fail=$((trail_fail + 1))
                        ;;
                esac
            fi
        done <<< "$trail_info"

        if [[ $trail_fail -gt 0 ]]; then
            log_error "Started $trail_ok, skipped $trail_skip, failed $trail_fail audit trail(s) for: $target_name"
            failed_count=$((failed_count + 1))
        else
            log_info "Started $trail_ok, skipped $trail_skip audit trail(s) for: $target_name"
            started_count=$((started_count + 1))
        fi
    done

    return 0
}

# =============================================================================
# MAIN
# =============================================================================

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"

    # Setup error handling
    setup_error_handling

    # Parse arguments and validate
    parse_args "$@"
    validate_inputs

    # Resolve targets then either list or start audit trails
    if resolve_targets && [[ ${#RESOLVED_TARGETS[@]} -gt 0 ]]; then
        if [[ "${LIST_MODE}" == "true" ]]; then
            list_audit_trails
        else
            start_audit_trails

            # Summary
            log_info "Audit trail start summary:"
            log_info "  Targets processed: ${#RESOLVED_TARGETS[@]}"
            log_info "  Successfully started: ${started_count}"
            log_info "  Failed starts: ${failed_count}"

            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "  [DRY-RUN] No actual changes were made"
            fi

            if [[ ${failed_count} -eq 0 ]]; then
                log_info "All audit trails started successfully"
                exit 0
            else
                die "${failed_count} audit trail(s) failed to start" 1
            fi
        fi
    else
        if [[ "${LIST_MODE}" == "true" ]]; then
            log_warn "No targets found matching criteria"
            exit 0
        else
            die "No targets available for audit trail start" 1
        fi
    fi
}

# Parse arguments and run
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

main "$@"
