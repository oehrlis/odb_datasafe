#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: uninstall_all_datasafe_services.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.06.29
# Version....: v1.0.1
# Purpose....: Wrapper: uninstall all Oracle Data Safe systemd services.
#              Discovers installed services via systemctl (catches orphaned services
#              where CONNECTOR_BASE may no longer exist) and delegates per-connector
#              uninstall to install_datasafe_service.sh.
# Notes......: Root only for --uninstall; --list works as any user.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.21 oehrli - initial version
# 2026.06.25 oehrli - add stop_service with oradba_dsctl.sh integration
# 2026.06.29 oehrli - refactored to thin wrapper around install_datasafe_service.sh
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${INSTALLER:-${SCRIPT_DIR}/install_datasafe_service.sh}"

# Mode flags
LIST_ONLY=false
UNINSTALL_MODE=false
DRY_RUN=false
FORCE=false
USE_COLOR=true

# Colors
RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''

init_colors() {
    if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        BOLD='\033[1m'
        NC='\033[0m'
    fi
}

print_message() {
    local level="$1"
    shift
    local message="$*"
    case "$level" in
        ERROR) echo -e "${RED}[ERROR]:${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[OK]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]:${NC} $message" ;;
        INFO) echo -e "${BLUE}[INFO]${NC}  $message" ;;
        STEP) echo -e "${BOLD}▶${NC}  $message" ;;
        *) echo "$message" ;;
    esac
}

# ------------------------------------------------------------------------------
# Function: usage
# ------------------------------------------------------------------------------
usage() {
    cat << EOF
Oracle Data Safe Service Uninstaller (wrapper)
Version: v1.0.1

Usage:
  $SCRIPT_NAME [OPTIONS]

Description:
  Uninstall all Oracle Data Safe On-Premises Connector systemd services.
  Discovers installed services from systemctl — works even when CONNECTOR_BASE
  is no longer present. Delegates per-connector uninstall to:
    ${INSTALLER}

Options:
  -l, --list        List all installed services (no root needed)
  -u, --uninstall   Uninstall all services (REQUIRES ROOT)
  -f, --force       Skip confirmation prompt (with --uninstall)
  -d, --dry-run     Show what would be removed without making changes
      --no-color    Disable colored output
  -h, --help        Show this help message

Examples:
  # List all installed services (as oracle user)
  $SCRIPT_NAME --list

  # Dry-run: see what would be removed
  sudo $SCRIPT_NAME --uninstall --dry-run

  # Interactive uninstall
  sudo $SCRIPT_NAME --uninstall

  # Force uninstall without confirmation
  sudo $SCRIPT_NAME --uninstall --force

What Gets Removed:
  - All oracle_datasafe_*.service files from /etc/systemd/system/
  - All related sudoers configurations from /etc/sudoers.d/
  - Services are stopped and disabled before removal

What Is Preserved:
  - Original connector installations in \$CONNECTOR_BASE
  - Local configuration files in connector etc/ directories
  - SERVICE_README.md files

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: discover_installed_services
# Purpose.: List installed oracle_datasafe_* services via systemctl
# ------------------------------------------------------------------------------
discover_installed_services() {
    systemctl list-unit-files 'oracle_datasafe_*.service' --no-legend 2> /dev/null \
        | awk '{print $1}' || true
}

# ------------------------------------------------------------------------------
# Function: list_services
# ------------------------------------------------------------------------------
list_services() {
    print_message STEP "Installed Data Safe Connector services"
    echo

    local -a services=()
    while IFS= read -r svc; do
        [[ -n "${svc}" ]] && services+=("${svc}")
    done < <(discover_installed_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        print_message INFO "No Data Safe Connector services installed"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local idx=1
    for svc in "${services[@]}"; do
        local status_label
        if systemctl is-active "${svc}" &> /dev/null; then
            status_label="${GREEN}ACTIVE${NC}"
        else
            status_label="${YELLOW}INACTIVE${NC}"
        fi
        printf "%2d. %-50s [" "${idx}" "${svc}"
        echo -e "${status_label}]"
        [[ -f "/etc/systemd/system/${svc}" ]] && echo "    /etc/systemd/system/${svc}"
        idx=$((idx + 1))
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#services[@]} service(s)"
    return 0
}

# ------------------------------------------------------------------------------
# Function: parse_arguments
# ------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l | --list)
                LIST_ONLY=true
                shift
                ;;
            -u | --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -f | --force)
                FORCE=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            -h | --help) usage ;;
            *)
                print_message ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    if ! $LIST_ONLY && ! $UNINSTALL_MODE; then
        LIST_ONLY=true
    fi
}

# ------------------------------------------------------------------------------
# Function: main
# ------------------------------------------------------------------------------
main() {
    parse_arguments "$@"
    init_colors

    if ! [[ -x "${INSTALLER}" ]]; then
        print_message ERROR "Installer not found or not executable: ${INSTALLER}"
        exit 1
    fi

    if $LIST_ONLY; then
        list_services || true
        if $UNINSTALL_MODE; then echo; fi
    fi

    if ! $UNINSTALL_MODE; then
        echo
        print_message INFO "To uninstall services, run: sudo $SCRIPT_NAME --uninstall"
        exit 0
    fi

    # Require root for uninstall
    if [[ $EUID -ne 0 ]] && ! $DRY_RUN; then
        print_message ERROR "--uninstall requires root privileges"
        print_message INFO "Run: sudo $SCRIPT_NAME --uninstall"
        exit 1
    fi

    local -a services=()
    while IFS= read -r svc; do
        [[ -n "${svc}" ]] && services+=("${svc}")
    done < <(discover_installed_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        print_message INFO "No Data Safe Connector services to uninstall"
        exit 0
    fi

    # Confirm unless --force or --dry-run
    if ! $FORCE && ! $DRY_RUN; then
        echo
        echo "Services to be removed:"
        for svc in "${services[@]}"; do echo "  - ${svc}"; done
        echo
        local answer
        read -rp "Remove all these services? [y/N]: " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Operation cancelled"
            exit 0
        fi
    fi

    # Build extra args to pass through to installer
    local -a extra_args=(--yes)
    $DRY_RUN && extra_args+=(--dry-run)
    [[ "$USE_COLOR" == "false" ]] && extra_args+=(--no-color)

    local -a ok_list=() fail_list=()

    for svc in "${services[@]}"; do
        local conn="${svc#oracle_datasafe_}"
        conn="${conn%.service}"
        echo
        print_message STEP "Uninstalling: ${svc}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        local rc=0
        if "${INSTALLER}" --uninstall -n "${conn}" "${extra_args[@]}"; then
            ok_list+=("${conn}")
        else
            rc=$?
            fail_list+=("${conn}")
            print_message WARNING "Failed (exit ${rc}): ${conn}"
        fi
    done

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message STEP "Uninstall Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for c in "${ok_list[@]+"${ok_list[@]}"}"; do print_message SUCCESS "${c}"; done
    for c in "${fail_list[@]+"${fail_list[@]}"}"; do print_message ERROR "${c} (FAILED)"; done
    echo
    print_message INFO "Total: ${#services[@]}  OK: ${#ok_list[@]}  FAILED: ${#fail_list[@]}"

    [[ ${#fail_list[@]} -eq 0 ]] || exit 1
}

main "$@"
# - EOF ------------------------------------------------------------------------
