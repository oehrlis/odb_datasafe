#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: uninstall_all_datasafe_services.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.02.19
# Version....: v0.7.0
# Purpose....: Uninstall all Oracle Data Safe On-Premises Connector systemd services
# Notes......: Works as regular user for listing. Root only for uninstall operations.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.21 oehrli - refactored to allow non-root listing and checking
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
# shellcheck disable=SC2034
SCRIPT_VERSION="v1.1.0"

# Mode flags
LIST_ONLY=false
UNINSTALL_MODE=false
DRY_RUN=false
INTERACTIVE=true
FORCE=false
USE_COLOR=true

# Colors
RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''

# ------------------------------------------------------------------------------
# Function: init_colors
# Purpose.: Initialize ANSI color variables
# Args....: None
# Returns.: 0 on success
# Output..: None
# ------------------------------------------------------------------------------
# Initialize colors
init_colors() {
    if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        BOLD='\033[1m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
    fi
}

# ------------------------------------------------------------------------------
# Function: print_message
# Purpose.: Print a formatted message with optional color
# Args....: $1 - Message level
#           $@ - Message text
# Returns.: 0 on success
# Output..: Message to stdout/stderr
# ------------------------------------------------------------------------------
# Print message
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
# Purpose.: Display usage information and exit
# Args....: None
# Returns.: 0 (exits script)
# Output..: Usage text to stdout
# ------------------------------------------------------------------------------
# Usage
usage() {
    cat << EOF
Usage:
    $SCRIPT_NAME [OPTIONS]

Description:
    Manage Oracle Data Safe On-Premises Connector systemd services.
    Works in two modes:
      1. List: View installed services (no root needed)
      2. Uninstall: Remove services from system (requires root)

Options:
    -l, --list                List installed services only (no root needed)
    -u, --uninstall           Uninstall all services (REQUIRES ROOT)
    -f, --force               Force removal without confirmation (with --uninstall)
    -d, --dry-run             Show what would be done without making changes
        --no-color            Disable colored output
    -h, --help                Show this help message

Examples:
    # List all installed services (as oracle user)
    $SCRIPT_NAME --list
    $SCRIPT_NAME  # same as --list

    # Dry-run uninstall (shows what would be removed)
    sudo $SCRIPT_NAME --uninstall --dry-run

    # Interactive uninstall (asks for confirmation)
    sudo $SCRIPT_NAME --uninstall

    # Force uninstall without confirmation (as root)
    sudo $SCRIPT_NAME --uninstall --force

What Gets Removed:
    - All oracle_datasafe_*.service files from /etc/systemd/system/
    - All related sudoers configurations from /etc/sudoers.d/
    - Services are stopped and disabled before removal

What Is Preserved:
    - Original connector installations in \$CONNECTOR_BASE
    - Local configuration files in connector etc/ directories
    - SERVICE_README.md files

Notes:
    - REQUIRES ROOT: --uninstall
    - NO ROOT NEEDED: --list, default behavior
    - To reinstall: sudo install_datasafe_service.sh --install -n <connector>

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: check_root
# Purpose.: Validate root requirements for uninstall operations
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
# Check if running as root (only for uninstall operations)
check_root() {
    # Root only required for uninstall
    if $UNINSTALL_MODE; then
        if [[ $EUID -ne 0 ]]; then
            if $DRY_RUN; then
                print_message WARNING "Not running as root (dry-run mode)"
                return 0
            fi
            print_message ERROR "--uninstall requires root privileges"
            print_message INFO "Run: sudo $SCRIPT_NAME --uninstall"
            exit 1
        fi
    else
        # Not required for list mode
        if [[ $EUID -eq 0 ]] && ! $DRY_RUN; then
            print_message WARNING "Running as root for list operation"
            print_message INFO "Tip: --list works as regular user"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: discover_services
# Purpose.: Discover installed Data Safe services
# Args....: None
# Returns.: 0 on success
# Output..: Service names to stdout
# ------------------------------------------------------------------------------
# Discover installed services
discover_services() {
    local -a services=()

    while IFS= read -r service; do
        [[ -n "$service" ]] && services+=("$service")
    done < <(systemctl list-unit-files 'oracle_datasafe_*.service' --no-legend 2> /dev/null | awk '{print $1}')

    printf '%s\n' "${services[@]}"
}

# ------------------------------------------------------------------------------
# Function: find_sudoers_files
# Purpose.: Find matching sudoers files
# Args....: $1 - Pattern to match
# Returns.: 0 on success
# Output..: Matching file paths to stdout
# ------------------------------------------------------------------------------
# Find sudoers files
find_sudoers_files() {
    local pattern="$1"
    find /etc/sudoers.d/ -type f -name "*datasafe*" 2> /dev/null | grep -E "$pattern" || true
}

# ------------------------------------------------------------------------------
# Function: find_readme_files
# Purpose.: Find connector README files
# Args....: $1 - Base directory (optional)
# Returns.: 0 on success
# Output..: Matching file paths to stdout
# ------------------------------------------------------------------------------
# Find README files
find_readme_files() {
    local base="${1:-/appl/oracle/product/dsconnect}"
    find "$base" -type f -name "SERVICE_README.md" 2> /dev/null || true
}

# ------------------------------------------------------------------------------
# Function: list_services
# Purpose.: List installed services and related files
# Args....: None
# Returns.: 0 on success, 1 when none found
# Output..: Service listing to stdout
# ------------------------------------------------------------------------------
# List services
list_services() {
    print_message STEP "Discovering installed Data Safe Connector services"
    echo

    local -a services
    mapfile -t services < <(discover_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        print_message INFO "No Data Safe Connector services found"
        return 1
    fi

    echo "Found services:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local idx=1
    for service in "${services[@]}"; do
        local connector_name="${service#oracle_datasafe_}"
        connector_name="${connector_name%.service}"
        local status

        if systemctl is-active "$service" &> /dev/null; then
            status="${GREEN}ACTIVE${NC}"
        else
            status="${YELLOW}INACTIVE${NC}"
        fi

        printf "%2d. %-50s [" "$idx" "$service"
        echo -e "${status}]"

        # Find related files
        local service_file="/etc/systemd/system/$service"
        [[ -f "$service_file" ]] && echo "    System service: $service_file"

        # Check for local config
        local connector_base="${CONNECTOR_BASE:-${ORACLE_BASE:-/u01/app/oracle}/product}"
        local local_config="$connector_base/${connector_name}/etc/systemd/$service"
        [[ -f "$local_config" ]] && echo "    Local config:   $local_config"

        local sudoers_file="/etc/sudoers.d/oracle-datasafe-${connector_name}"
        if [[ ! -f "$sudoers_file" ]]; then
            sudoers_file="/etc/sudoers.d/*-datasafe-${connector_name}"
        fi
        [[ -f "$sudoers_file" ]] && echo "    Sudoers config: $sudoers_file"

        echo
        idx=$((idx + 1))
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#services[@]} service(s) found"

    return 0
}

# ------------------------------------------------------------------------------
# Function: remove_all_services
# Purpose.: Remove all Data Safe services from the system
# Args....: None
# Returns.: 0 on success
# Output..: Log messages and summary
# ------------------------------------------------------------------------------
# Remove all services
remove_all_services() {
    local -a services
    mapfile -t services < <(discover_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        print_message INFO "No services to remove"
        return 0
    fi

    echo
    print_message STEP "Removing ${#services[@]} Data Safe Connector service(s)"
    echo

    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - No changes will be made"
        echo
        echo "Would remove:"
        for service in "${services[@]}"; do
            echo "  - $service"
            echo "    /etc/systemd/system/$service"

            local connector_name="${service#oracle_datasafe_}"
            connector_name="${connector_name%.service}"

            local sudoers_files
            sudoers_files="$(find_sudoers_files "$connector_name")"
            if [[ -n "$sudoers_files" ]]; then
                while IFS= read -r file; do
                    echo "    $file"
                done <<< "$sudoers_files"
            fi
        done
        return 0
    fi

    # Confirm if interactive
    if $INTERACTIVE && ! $FORCE; then
        echo "Services to be removed:"
        for service in "${services[@]}"; do
            echo "  - $service"
        done
        echo
        read -rp "Remove all these services? [y/N]: " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Operation cancelled"
            return 0
        fi
    fi

    # Remove each service
    local success_count=0
    local fail_count=0

    for service in "${services[@]}"; do
        echo
        print_message INFO "Removing: $service"

        local connector_name="${service#oracle_datasafe_}"
        connector_name="${connector_name%.service}"

        # Stop service
        if systemctl is-active "$service" &> /dev/null; then
            print_message INFO "Stopping service"
            if systemctl stop "$service" 2> /dev/null; then
                print_message SUCCESS "Service stopped"
            else
                print_message WARNING "Failed to stop service"
            fi
        fi

        # Disable service
        if systemctl is-enabled "$service" &> /dev/null; then
            print_message INFO "Disabling service"
            systemctl disable "$service" 2> /dev/null || true
        fi

        # Remove service file
        local service_file="/etc/systemd/system/$service"
        if [[ -f "$service_file" ]]; then
            print_message INFO "Removing service file"
            rm -f "$service_file"
        fi

        # Remove sudoers files
        local sudoers_files
        sudoers_files="$(find_sudoers_files "$connector_name")"
        if [[ -n "$sudoers_files" ]]; then
            print_message INFO "Removing sudoers configuration"
            while IFS= read -r file; do
                rm -f "$file"
            done <<< "$sudoers_files"
        fi

        # Remove README (optional, might want to keep)
        # Commenting out to preserve documentation
        # local readme_pattern="*${connector_name}*/SERVICE_README.md"
        # find /appl/oracle/product/dsconnect -type f -path "$readme_pattern" -delete 2>/dev/null || true

        print_message SUCCESS "Removed: $service"
        success_count=$((success_count + 1))
    done

    # Reload systemd
    print_message INFO "Reloading systemd daemon"
    systemctl daemon-reload

    # Summary
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message SUCCESS "Uninstallation Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Services removed: $success_count"
    [[ $fail_count -gt 0 ]] && echo "Failed: $fail_count"
    echo
    print_message INFO "Original connector installations preserved"
    print_message INFO "Local configuration files preserved in connector etc/ directories"
    print_message INFO "To reinstall: sudo install_datasafe_service.sh --install -n <connector>"
}

# ------------------------------------------------------------------------------
# Function: parse_arguments
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global flags
# ------------------------------------------------------------------------------
# Parse arguments
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
                INTERACTIVE=false
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
            -h | --help)
                usage
                ;;
            *)
                print_message ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Default to list mode if no mode specified
    if ! $LIST_ONLY && ! $UNINSTALL_MODE; then
        LIST_ONLY=true
    fi
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
# Main
main() {
    parse_arguments "$@"
    init_colors
    check_root

    if ! list_services; then
        exit 0
    fi

    # Only proceed with uninstall if requested
    if $UNINSTALL_MODE; then
        echo
        remove_all_services
    else
        # List mode - show helpful message
        echo
        print_message INFO "To uninstall services, run: sudo $SCRIPT_NAME --uninstall"
    fi
}

main "$@"
# - EOF ------------------------------------------------------------------------
