#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: uninstall_all_datasafe_services.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.11
# Version....: v1.0.0
# Purpose....: Uninstall all Oracle Data Safe On-Premises Connector systemd services
# Notes......: Must be run as root. Discovers and removes all datasafe services.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
# shellcheck disable=SC2034
SCRIPT_VERSION="v1.0.0"

# Mode flags
DRY_RUN=false
INTERACTIVE=true
FORCE=false
USE_COLOR=true

# Colors
RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''

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

# Print message
print_message() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        ERROR)   echo -e "${RED}❌ ERROR:${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}✅${NC} $message" ;;
        WARNING) echo -e "${YELLOW}⚠️  WARNING:${NC} $message" ;;
        INFO)    echo -e "${BLUE}ℹ️${NC}  $message" ;;
        STEP)    echo -e "${BOLD}▶${NC}  $message" ;;
        *)       echo "$message" ;;
    esac
}

# Usage
usage() {
    cat << EOF
${BOLD}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${BOLD}Description:${NC}
    Uninstall all Oracle Data Safe On-Premises Connector systemd services.
    Discovers all installed services and removes them with related configurations.

${BOLD}Options:${NC}
    -f, --force               Force removal without confirmation
    -d, --dry-run             Show what would be done without making changes
        --no-color            Disable colored output
    -h, --help                Show this help message

${BOLD}Examples:${NC}
    # List what would be removed (dry-run)
    $SCRIPT_NAME --dry-run

    # Interactive removal (asks for confirmation)
    $SCRIPT_NAME

    # Force removal without confirmation
    $SCRIPT_NAME --force

${BOLD}What Gets Removed:${NC}
    - All oracle_datasafe_*.service files
    - All related sudoers configurations
    - All SERVICE_README.md files in connector directories

${BOLD}Notes:${NC}
    - Must be run as root
    - Services are stopped before removal
    - Original connector files are NOT removed
    - Only systemd services and configurations are removed

EOF
    exit 0
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        if $DRY_RUN; then
            print_message WARNING "Not running as root (dry-run mode)"
            return 0
        fi
        print_message ERROR "This script must be run as root"
        exit 1
    fi
}

# Discover installed services
discover_services() {
    local -a services=()
    
    while IFS= read -r service; do
        [[ -n "$service" ]] && services+=("$service")
    done < <(systemctl list-unit-files 'oracle_datasafe_*.service' --no-legend 2>/dev/null | awk '{print $1}')
    
    printf '%s\n' "${services[@]}"
}

# Find sudoers files
find_sudoers_files() {
    local pattern="$1"
    find /etc/sudoers.d/ -type f -name "*datasafe*" 2>/dev/null | grep -E "$pattern" || true
}

# Find README files
find_readme_files() {
    local base="${1:-/appl/oracle/product/dsconnect}"
    find "$base" -type f -name "SERVICE_README.md" 2>/dev/null || true
}

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
        
        if systemctl is-active "$service" &>/dev/null; then
            status="${GREEN}ACTIVE${NC}"
        else
            status="${YELLOW}INACTIVE${NC}"
        fi
        
        printf "%2d. %-50s [%s]\n" "$idx" "$service" "$status"
        
        # Find related files
        local service_file="/etc/systemd/system/$service"
        [[ -f "$service_file" ]] && echo "    Service: $service_file"
        
        local sudoers_file="/etc/sudoers.d/oracle-datasafe-${connector_name}"
        if [[ ! -f "$sudoers_file" ]]; then
            sudoers_file="/etc/sudoers.d/oravw-datasafe-${connector_name}"
        fi
        [[ -f "$sudoers_file" ]] && echo "    Sudoers: $sudoers_file"
        
        echo
        ((idx++))
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#services[@]} service(s) found"
    
    return 0
}

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
        if systemctl is-active "$service" &>/dev/null; then
            print_message INFO "Stopping service"
            if systemctl stop "$service" 2>/dev/null; then
                print_message SUCCESS "Service stopped"
            else
                print_message WARNING "Failed to stop service"
            fi
        fi
        
        # Disable service
        if systemctl is-enabled "$service" &>/dev/null; then
            print_message INFO "Disabling service"
            systemctl disable "$service" 2>/dev/null || true
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
        ((success_count++))
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
    print_message INFO "Original connector installations are preserved"
    print_message INFO "Only systemd services and sudo configurations were removed"
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                FORCE=true
                INTERACTIVE=false
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_message ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main
main() {
    parse_arguments "$@"
    init_colors
    check_root
    
    if ! list_services; then
        exit 0
    fi
    
    echo
    remove_all_services
}

main "$@"
# - EOF ------------------------------------------------------------------------
