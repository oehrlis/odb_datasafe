#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: install_datasafe_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.02.19
# Version....: v0.7.0
# Purpose....: Install and manage Oracle Data Safe On-Premises Connector as systemd service
#              Generic solution for any connector with automatic discovery and configuration
# Notes......: Works as regular user for config preparation. Root only for system installation.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.11 oehrli - initial version with auto-discovery and interactive mode
# 2026.01.21 oehrli - refactored to allow non-root config generation
# ------------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------------------
# Default Configuration
# ------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="v1.1.0"

# Default paths (can be overridden)
DEFAULT_CONNECTOR_BASE="${ORACLE_BASE:-/u01/app/oracle}/product"
DEFAULT_USER="oracle"
DEFAULT_GROUP="dba"
DEFAULT_JAVA_HOME="${ORACLE_BASE:-/u01/app/oracle}/product/jdk"

# Runtime variables
CONNECTOR_BASE="${CONNECTOR_BASE:-$DEFAULT_CONNECTOR_BASE}"
CONNECTOR_NAME=""
CONNECTOR_HOME=""
CONNECTOR_ETC=""
CMAN_NAME=""
CMAN_HOME=""
CMAN_CTL=""
OS_USER="${OS_USER:-$DEFAULT_USER}"
OS_GROUP="${OS_GROUP:-$DEFAULT_GROUP}"
JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"

# Mode flags
PREPARE_MODE=false
INSTALL_MODE=false
UNINSTALL_MODE=false
DRY_RUN=false
TEST_MODE=false
INTERACTIVE=true
LIST_MODE=false
CHECK_MODE=false
VERBOSE=false
SKIP_SUDO=false
USE_COLOR=true

# Service configuration
SERVICE_NAME=""
SERVICE_FILE=""
SUDOERS_FILE=""
README_FILE=""

# Colors for output (will be set in init_colors)
RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

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
# Print colored message
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
# Usage information
usage() {
    cat << EOF
Oracle Data Safe Service Installer
Version: $SCRIPT_VERSION

Usage:
  $SCRIPT_NAME [OPTIONS]

Description:
  Manage Oracle Data Safe On-Premises Connector as a systemd service.
  Works in two phases:
    1. Prepare: Generate config files in connector etc/ directory (as oracle/oradba user)
    2. Install: Copy configs to system locations (requires root)

Workflow Options:
    --prepare               Generate service configs in connector etc/ (default, no root needed)
    --install               Install prepared configs to system (REQUIRES ROOT)
    --uninstall             Remove service from system (REQUIRES ROOT)
    
Configuration Options:
    -n, --connector <name>  Connector name (directory name under base path)
    -b, --base <path>       Connector base directory (default: \$ORACLE_BASE/product)
    -u, --user <user>       OS user for service (default: $DEFAULT_USER)
    -g, --group <group>     OS group for service (default: $DEFAULT_GROUP)
    -j, --java-home <path>  JAVA_HOME path (default: \$ORACLE_BASE/product/jdk)
    
Query Options:
    -l, --list              List all available connectors (no root needed)
    -c, --check             Check if service is installed (no root needed)
    
Control Options:
    -y, --yes               Non-interactive mode (use defaults/provided values)
    -d, --dry-run           Show what would be done without making changes
    -t, --test              Test/demo mode (shows what would happen)
    -v, --verbose           Verbose output
    --skip-sudo             Skip sudo configuration generation
    --no-color              Disable colored output
    -h, --help              Show this help message

Examples:
  # List available connectors (as oracle user)
  $SCRIPT_NAME --list

  # Prepare service configuration (as oracle user)
  $SCRIPT_NAME --prepare -n my-connector
  $SCRIPT_NAME -n my-connector  # same as --prepare

  # Install to system (as root, after prepare)
  sudo $SCRIPT_NAME --install -n my-connector

  # Complete workflow (prepare + install)
  $SCRIPT_NAME --prepare -n my-connector
  sudo $SCRIPT_NAME --install -n my-connector

  # Check if service is installed (as oracle user)
  $SCRIPT_NAME --check -n my-connector

  # Remove service (as root)
  sudo $SCRIPT_NAME --uninstall -n my-connector

  # Interactive preparation (as oracle user)
  $SCRIPT_NAME

  # Custom configuration
  $SCRIPT_NAME -n my-connector -u oracle -g dba -j /opt/java/jdk

  # Dry-run install (as root)
  sudo $SCRIPT_NAME --install -n my-connector --dry-run

Environment Variables:
  ORACLE_BASE               Oracle base directory (default: /u01/app/oracle)
  CONNECTOR_BASE            Override default connector base path
  OS_USER                   Override default OS user
  OS_GROUP                  Override default OS group
  JAVA_HOME                 Override default Java home

Notes:
  - REQUIRES ROOT: --install, --uninstall
  - NO ROOT NEEDED: --prepare, --list, --check, default behavior
  - Default search path: \$ORACLE_BASE/product/<connector-name>/
  - Config files stored in: \$CONNECTOR_HOME/etc/systemd/
  - Each connector gets a unique service: oracle_datasafe_<connector-name>.service
  - Auto-detects CMAN instance name from cman.ora

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: check_root
# Purpose.: Validate root requirements for install/uninstall operations
# Args....: None
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
# Check if running as root (only for install/uninstall operations)
check_root() {
    # Root only required for install/uninstall
    if $INSTALL_MODE || $UNINSTALL_MODE; then
        if [[ $EUID -ne 0 ]]; then
            if $DRY_RUN || $TEST_MODE; then
                print_message WARNING "Not running as root (dry-run/test mode)"
                return 0
            fi
            print_message ERROR "--install and --uninstall require root privileges"
            print_message INFO "Run: sudo $SCRIPT_NAME --install -n $CONNECTOR_NAME"
            exit 1
        fi
    else
        # Not required for prepare, list, check
        if [[ $EUID -eq 0 ]] && ! $DRY_RUN && ! $TEST_MODE; then
            print_message WARNING "Running as root for non-install operation"
            print_message INFO "Tip: --prepare, --list, --check work as regular user"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: discover_connectors
# Purpose.: Discover available connector directories
# Args....: $1 - Base directory (optional)
# Returns.: 0 on success, 1 on error
# Output..: Connector names to stdout
# ------------------------------------------------------------------------------
# Discover available connectors
discover_connectors() {
    local base="${1:-${CONNECTOR_BASE}}"
    local -a connectors=()

    if [[ ! -d "$base" ]]; then
        print_message ERROR "Connector base directory not found: $base"
        print_message INFO "Tip: Set ORACLE_BASE or use --base /path/to/connectors"
        return 1
    fi

    while IFS= read -r -d '' dir; do
        local name
        name="$(basename "$dir")"
        # Skip jdk and other non-connector directories
        if [[ "$name" != "jdk" && -d "$dir/oracle_cman_home" ]]; then
            connectors+=("$name")
        fi
    done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)

    printf '%s\n' "${connectors[@]}"
}

# ------------------------------------------------------------------------------
# Function: list_connectors
# Purpose.: List available connectors and status
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Connector list to stdout
# ------------------------------------------------------------------------------
# List available connectors
list_connectors() {
    print_message STEP "Scanning for Data Safe connectors in: $CONNECTOR_BASE"
    echo

    local -a connectors
    mapfile -t connectors < <(discover_connectors "$CONNECTOR_BASE")

    if [[ ${#connectors[@]} -eq 0 ]]; then
        print_message WARNING "No connectors found in $CONNECTOR_BASE"
        return 1
    fi

    echo "Available connectors:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local idx=1
    for connector in "${connectors[@]}"; do
        local conn_path="$CONNECTOR_BASE/$connector"
        local cman_home="$conn_path/oracle_cman_home"
        local service_name="oracle_datasafe_${connector}.service"
        local installed=""

        if systemctl list-unit-files "$service_name" &> /dev/null; then
            installed="${GREEN}[INSTALLED]${NC}"
        else
            installed="${YELLOW}[NOT INSTALLED]${NC}"
        fi

        printf "%2d. %-50s " "$idx" "$connector"
        echo -e "$installed"
        printf "    Path: %s\n" "$conn_path"

        # Try to get CMAN name from cman.ora
        local cman_ora="$cman_home/network/admin/cman.ora"
        if [[ -f "$cman_ora" ]]; then
            local cman_name
            cman_name="$(grep -E '^\s*[A-Za-z0-9_]+\s*=' "$cman_ora" 2> /dev/null | head -1 | awk -F= '{print $1}' | tr -d ' ' || echo "N/A")"
            printf "    CMAN: %s\n" "$cman_name"
        fi
        echo
        idx=$((idx + 1))
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#connectors[@]} connector(s) found"
}

# ------------------------------------------------------------------------------
# Function: validate_connector
# Purpose.: Validate connector directory and prerequisites
# Args....: $1 - Connector name
#           $2 - Base directory
# Returns.: 0 on success, 1 on error
# Output..: Log messages
# ------------------------------------------------------------------------------
# Validate connector directory
validate_connector() {
    local connector="$1"
    local base="$2"

    CONNECTOR_HOME="$base/$connector"
    CONNECTOR_ETC="$CONNECTOR_HOME/etc/systemd"

    if [[ ! -d "$CONNECTOR_HOME" ]]; then
        print_message ERROR "Connector directory not found: $CONNECTOR_HOME"
        return 1
    fi

    CMAN_HOME="$CONNECTOR_HOME/oracle_cman_home"
    if [[ ! -d "$CMAN_HOME" ]]; then
        print_message ERROR "CMAN home not found: $CMAN_HOME"
        return 1
    fi

    CMAN_CTL="$CMAN_HOME/bin/cmctl"
    if [[ ! -x "$CMAN_CTL" ]]; then
        print_message ERROR "cmctl not found or not executable: $CMAN_CTL"
        return 1
    fi

    # Try to detect CMAN instance name from cman.ora
    local cman_ora="$CMAN_HOME/network/admin/cman.ora"
    if [[ ! -f "$cman_ora" ]]; then
        print_message ERROR "cman.ora not found: $cman_ora"
        return 1
    fi

    # Extract CMAN instance name (first parameter name in cman.ora)
    CMAN_NAME="$(grep -E '^\s*[A-Za-z0-9_]+\s*=' "$cman_ora" 2> /dev/null | head -1 | awk -F= '{print $1}' | tr -d ' ')"

    if [[ -z "$CMAN_NAME" ]]; then
        print_message ERROR "Could not detect CMAN instance name from $cman_ora"
        return 1
    fi

    # Validate Java
    if [[ ! -d "$JAVA_HOME" ]]; then
        print_message ERROR "JAVA_HOME not found: $JAVA_HOME"
        return 1
    fi

    local java_bin="$JAVA_HOME/bin/java"
    if [[ ! -x "$java_bin" ]]; then
        print_message ERROR "Java executable not found: $java_bin"
        return 1
    fi

    # Validate user and group (only for install operations)
    if $INSTALL_MODE && ! $TEST_MODE && ! $DRY_RUN; then
        if ! id "$OS_USER" &> /dev/null; then
            print_message ERROR "User does not exist: $OS_USER"
            return 1
        fi

        if ! getent group "$OS_GROUP" &> /dev/null; then
            print_message ERROR "Group does not exist: $OS_GROUP"
            return 1
        fi
    fi

    # Create etc directory for prepare mode
    if $PREPARE_MODE && [[ ! -d "$CONNECTOR_ETC" ]]; then
        mkdir -p "$CONNECTOR_ETC" || {
            print_message ERROR "Cannot create directory: $CONNECTOR_ETC"
            return 1
        }
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Function: select_connector_interactive
# Purpose.: Prompt for connector selection interactively
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Prompts and status messages
# ------------------------------------------------------------------------------
# Interactive connector selection
select_connector_interactive() {
    local -a connectors
    mapfile -t connectors < <(discover_connectors "$CONNECTOR_BASE")

    if [[ ${#connectors[@]} -eq 0 ]]; then
        print_message ERROR "No connectors found in $CONNECTOR_BASE"
        return 1
    fi

    echo
    echo "Available Data Safe On-Premises Connectors:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local idx=1
    for connector in "${connectors[@]}"; do
        printf "%2d. %s\n" "$idx" "$connector"
        idx=$((idx + 1))
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    local selection
    while true; do
        read -rp "Select connector (1-${#connectors[@]}) or 'q' to quit: " selection

        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            print_message INFO "Operation cancelled by user"
            exit 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#connectors[@]})); then
            CONNECTOR_NAME="${connectors[$((selection - 1))]}"
            break
        else
            print_message WARNING "Invalid selection. Please enter a number between 1 and ${#connectors[@]}"
        fi
    done

    print_message SUCCESS "Selected connector: $CONNECTOR_NAME"
}

# ------------------------------------------------------------------------------
# Function: generate_service_file
# Purpose.: Generate systemd service unit content
# Args....: None
# Returns.: 0 on success
# Output..: Service file content to stdout
# ------------------------------------------------------------------------------
# Generate service file content
generate_service_file() {
    cat << EOF
# ------------------------------------------------------------------------------
# Oracle Data Safe On-Premises Connector systemd service
# Connector: $CONNECTOR_NAME
# Generated: $(date)
# Managed by: $SCRIPT_NAME $SCRIPT_VERSION
# ------------------------------------------------------------------------------
[Unit]
Description=Oracle Data Safe On-Premises Connector ($CONNECTOR_NAME)
Documentation=https://docs.oracle.com/en/cloud/paas/data-safe/
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$OS_USER
Group=$OS_GROUP

# Environment
Environment="JAVA_HOME=$JAVA_HOME"
Environment="ORACLE_HOME=$CMAN_HOME"
Environment="PATH=$JAVA_HOME/bin:$CMAN_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Working directory
WorkingDirectory=$CONNECTOR_HOME

# Service management
ExecStart=$CMAN_CTL startup -c $CMAN_NAME
ExecStop=$CMAN_CTL shutdown -c $CMAN_NAME
ExecReload=$CMAN_CTL restart -c $CMAN_NAME

# Restart behavior
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=300

# Security
PrivateTmp=true
NoNewPrivileges=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=datasafe-$CONNECTOR_NAME

[Install]
WantedBy=multi-user.target
EOF
}

# ------------------------------------------------------------------------------
# Function: generate_sudoers_file
# Purpose.: Generate sudoers file content
# Args....: None
# Returns.: 0 on success
# Output..: Sudoers file content to stdout
# ------------------------------------------------------------------------------
# Generate sudoers file content
generate_sudoers_file() {
    cat << EOF
# ------------------------------------------------------------------------------
# Sudo configuration for Oracle Data Safe Connector: $CONNECTOR_NAME
# Generated: $(date)
# Managed by: $SCRIPT_NAME $SCRIPT_VERSION
# ------------------------------------------------------------------------------
# Allow $OS_USER to manage the Data Safe connector service
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl start $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl reload $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl status $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl is-active $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/systemctl is-enabled $SERVICE_NAME
$OS_USER ALL=(ALL) NOPASSWD: /bin/journalctl -u $SERVICE_NAME*
EOF
}

# ------------------------------------------------------------------------------
# Function: generate_readme
# Purpose.: Generate service README documentation
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Writes README file
# ------------------------------------------------------------------------------
# Generate README file
generate_readme() {
    local readme="$README_FILE"

    cat > "$readme" << EOF
# Oracle Data Safe On-Premises Connector Service
# Connector: $CONNECTOR_NAME
# Generated: $(date)

## Service Information

- **Service Name**: $SERVICE_NAME
- **Connector Name**: $CONNECTOR_NAME
- **Connector Path**: $CONNECTOR_HOME
- **CMAN Instance**: $CMAN_NAME
- **CMAN Home**: $CMAN_HOME
- **User**: $OS_USER
- **Group**: $OS_GROUP
- **Java Home**: $JAVA_HOME

## Service Management

### As root user:
\`\`\`bash
# Start service
systemctl start $SERVICE_NAME

# Stop service
systemctl stop $SERVICE_NAME

# Restart service
systemctl restart $SERVICE_NAME

# Check status
systemctl status $SERVICE_NAME

# Enable auto-start on boot
systemctl enable $SERVICE_NAME

# Disable auto-start on boot
systemctl disable $SERVICE_NAME
\`\`\`

### As $OS_USER user (with sudo):
\`\`\`bash
# Start service
sudo systemctl start $SERVICE_NAME

# Stop service
sudo systemctl stop $SERVICE_NAME

# Restart service
sudo systemctl restart $SERVICE_NAME

# Check status
sudo systemctl status $SERVICE_NAME
\`\`\`

## Log Management

### View logs (recent):
\`\`\`bash
sudo journalctl -u $SERVICE_NAME
\`\`\`

### View logs (follow):
\`\`\`bash
sudo journalctl -u $SERVICE_NAME -f
\`\`\`

### View logs (today):
\`\`\`bash
sudo journalctl -u $SERVICE_NAME --since today
\`\`\`

### View logs (last hour):
\`\`\`bash
sudo journalctl -u $SERVICE_NAME --since "1 hour ago"
\`\`\`

## Verification

### Check if service is running:
\`\`\`bash
systemctl is-active $SERVICE_NAME
\`\`\`

### Check if service is enabled:
\`\`\`bash
systemctl is-enabled $SERVICE_NAME
\`\`\`

### Verify CMAN is listening:
\`\`\`bash
netstat -tlnp | grep cmgw
# or
ss -tlnp | grep cmgw
\`\`\`

## Troubleshooting

### Service won't start:
1. Check service status: \`systemctl status $SERVICE_NAME\`
2. Check logs: \`journalctl -u $SERVICE_NAME --since "10 minutes ago"\`
3. Verify user permissions on $CONNECTOR_HOME
4. Check CMAN configuration: $CMAN_HOME/network/admin/cman.ora

### Connection issues:
1. Verify CMAN is running: \`ps aux | grep cmgw\`
2. Check listener ports: \`netstat -tlnp | grep cmgw\`
3. Review CMAN logs in $CONNECTOR_HOME/log/

## Configuration Files

- **Service file (local)**: $CONNECTOR_ETC/$SERVICE_NAME
- **Service file (system)**: /etc/systemd/system/$SERVICE_NAME
- **Sudo config (local)**: $CONNECTOR_ETC/$OS_USER-datasafe-$CONNECTOR_NAME
- **Sudo config (system)**: /etc/sudoers.d/$OS_USER-datasafe-$CONNECTOR_NAME
- **CMAN config**: $CMAN_HOME/network/admin/cman.ora
- **This README**: $README_FILE

## Installation Steps

This service was prepared but not yet installed. To install:

\`\`\`bash
# As root user:
sudo $SCRIPT_NAME --install -n $CONNECTOR_NAME
\`\`\`

## Uninstallation

To remove this service:
\`\`\`bash
sudo $SCRIPT_NAME --uninstall -n $CONNECTOR_NAME
\`\`\`

---
Generated by $SCRIPT_NAME $SCRIPT_VERSION
EOF

    chmod 644 "$readme"
}

# ------------------------------------------------------------------------------
# Function: prepare_service
# Purpose.: Prepare service configuration files (non-root)
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Log messages and generated files
# ------------------------------------------------------------------------------
# Prepare service configuration (non-root)
prepare_service() {
    print_message STEP "Preparing Data Safe Connector Service Configuration"
    echo

    # Set service and file names
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    SERVICE_FILE="$CONNECTOR_ETC/$SERVICE_NAME"
    SUDOERS_FILE="$CONNECTOR_ETC/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    README_FILE="$CONNECTOR_HOME/SERVICE_README.md"

    # Ensure etc directory exists
    if [[ ! -d "$CONNECTOR_ETC" ]]; then
        mkdir -p "$CONNECTOR_ETC" || {
            print_message ERROR "Cannot create directory: $CONNECTOR_ETC"
            return 1
        }
    fi

    # Display configuration
    echo "Configuration:"
    echo "  Connector Name....: $CONNECTOR_NAME"
    echo "  Connector Home....: $CONNECTOR_HOME"
    echo "  Config Directory..: $CONNECTOR_ETC"
    echo "  CMAN Instance.....: $CMAN_NAME"
    echo "  CMAN Home.........: $CMAN_HOME"
    echo "  Service Name......: $SERVICE_NAME"
    echo "  OS User...........: $OS_USER"
    if ! $SKIP_SUDO; then
        echo "  Sudo Config.......: Enabled"
    else
        echo "  Sudo Config.......: Skipped"
    fi
    echo

    # Handle dry-run or test mode
    if $DRY_RUN || $TEST_MODE; then
        local mode_name="DRY-RUN"
        [[ "$TEST_MODE" == "true" ]] && mode_name="TEST/DEMO"
        print_message INFO "$mode_name MODE - No changes will be made"
        echo
        echo "Would create:"
        echo "  - $SERVICE_FILE"
        if ! $SKIP_SUDO; then
            echo "  - $SUDOERS_FILE"
        fi
        echo "  - $README_FILE"
        echo
        echo "Service file content:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        generate_service_file
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ! $SKIP_SUDO; then
            echo
            echo "Sudoers file content:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            generate_sudoers_file
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
        return 0
    fi

    # Create service file
    print_message INFO "Creating service file: $SERVICE_FILE"
    generate_service_file > "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"

    # Create sudoers file (unless skipped)
    if ! $SKIP_SUDO; then
        print_message INFO "Creating sudoers configuration: $SUDOERS_FILE"
        generate_sudoers_file > "$SUDOERS_FILE"
        chmod 600 "$SUDOERS_FILE"
    else
        print_message INFO "Skipping sudoers configuration (--skip-sudo)"
    fi

    # Generate README
    print_message INFO "Creating service documentation: $README_FILE"
    generate_readme

    # Print summary
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message SUCCESS "Service Configuration Prepared"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Configuration files created in: $CONNECTOR_ETC"
    echo "  - $SERVICE_NAME (service definition)"
    if ! $SKIP_SUDO; then
        echo "  - ${OS_USER}-datasafe-${CONNECTOR_NAME} (sudo config)"
    fi
    echo
    echo "Documentation: $README_FILE"
    echo
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Review the generated files in: $CONNECTOR_ETC"
    echo "  2. Install to system (as root):"
    echo "     sudo $SCRIPT_NAME --install -n $CONNECTOR_NAME"
    echo
}

# ------------------------------------------------------------------------------
# Function: install_service
# Purpose.: Install service configuration to system (root)
# Args....: None
# Returns.: 0 on success, 1 on error
# Output..: Log messages and systemctl output
# ------------------------------------------------------------------------------
# Install service to system (requires root)
install_service() {
    print_message STEP "Installing Data Safe Connector Service to System"
    echo

    # Set service and file names
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    local local_service="$CONNECTOR_ETC/$SERVICE_NAME"
    local local_sudoers="$CONNECTOR_ETC/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    local system_service="/etc/systemd/system/$SERVICE_NAME"
    local system_sudoers="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"

    # Check if configs exist
    if [[ ! -f "$local_service" ]]; then
        print_message ERROR "Service file not found: $local_service"
        print_message INFO "Run: $SCRIPT_NAME --prepare -n $CONNECTOR_NAME"
        return 1
    fi

    # Display what will be installed
    echo "Installation plan:"
    echo "  Source........: $CONNECTOR_ETC"
    echo "  Service file..: $local_service"
    echo "               -> $system_service"
    if [[ -f "$local_sudoers" ]]; then
        echo "  Sudo config...: $local_sudoers"
        echo "               -> $system_sudoers"
    fi
    echo

    # Handle dry-run
    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - No changes will be made"
        echo
        echo "Would execute:"
        echo "  1. Copy $local_service to $system_service"
        if [[ -f "$local_sudoers" ]]; then
            echo "  2. Copy $local_sudoers to $system_sudoers"
            echo "  3. Validate sudoers syntax"
        fi
        echo "  4. systemctl daemon-reload"
        echo "  5. systemctl enable $SERVICE_NAME"
        echo "  6. systemctl start $SERVICE_NAME"
        return 0
    fi

    # Check if already installed
    if [[ -f "$system_service" ]]; then
        local answer="y"
        if $INTERACTIVE; then
            read -rp "Service already installed. Overwrite? [y/N]: " answer
        fi
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Installation cancelled"
            return 0
        fi
        # Stop existing service
        print_message INFO "Stopping existing service"
        systemctl stop "$SERVICE_NAME" 2> /dev/null || true
    fi

    # Copy service file
    print_message INFO "Installing service file to: $system_service"
    cp "$local_service" "$system_service"
    chmod 644 "$system_service"

    # Copy sudoers file if exists
    if [[ -f "$local_sudoers" ]]; then
        print_message INFO "Installing sudoers configuration to: $system_sudoers"
        cp "$local_sudoers" "$system_sudoers"
        chmod 440 "$system_sudoers"

        # Validate sudoers syntax
        if ! visudo -c -f "$system_sudoers" &> /dev/null; then
            print_message ERROR "Invalid sudoers syntax, removing file"
            rm -f "$system_sudoers"
            return 1
        fi
        print_message SUCCESS "Sudoers configuration validated"
    fi

    # Reload systemd
    print_message INFO "Reloading systemd daemon"
    systemctl daemon-reload

    # Enable service
    print_message INFO "Enabling service"
    systemctl enable "$SERVICE_NAME"

    # Start service
    print_message INFO "Starting service"
    if systemctl start "$SERVICE_NAME"; then
        print_message SUCCESS "Service started successfully"
    else
        print_message ERROR "Failed to start service"
        print_message INFO "Check status with: systemctl status $SERVICE_NAME"
        return 1
    fi

    # Wait a moment and check status
    sleep 2

    echo
    systemctl status "$SERVICE_NAME" --no-pager -l

    # Print summary
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message SUCCESS "Data Safe Connector Service Installed Successfully"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Service Name: $SERVICE_NAME"
    echo "User: $OS_USER"
    echo
    echo -e "${BOLD}Management Commands:${NC}"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl restart $SERVICE_NAME"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
    echo
}

# ------------------------------------------------------------------------------
# Function: check_service
# Purpose.: Check service installation status
# Args....: None
# Returns.: 0 on success
# Output..: Status details to stdout
# ------------------------------------------------------------------------------
# Check service status
check_service() {
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    local local_service="$CONNECTOR_ETC/$SERVICE_NAME"
    local local_sudoers="$CONNECTOR_ETC/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    local system_service="/etc/systemd/system/$SERVICE_NAME"
    local system_sudoers="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    local readme="$CONNECTOR_HOME/SERVICE_README.md"

    echo
    print_message STEP "Checking service status for connector: $CONNECTOR_NAME"
    echo

    # Check local configs
    echo "Local Configuration ($CONNECTOR_ETC):"
    echo "  Service file: $local_service"
    if [[ -f "$local_service" ]]; then
        print_message SUCCESS "Exists (prepared)"
    else
        print_message WARNING "Not found - run: $SCRIPT_NAME --prepare -n $CONNECTOR_NAME"
    fi

    echo
    echo "  Sudo config: $local_sudoers"
    if [[ -f "$local_sudoers" ]]; then
        print_message SUCCESS "Exists"
    else
        print_message WARNING "Not found"
    fi

    echo
    echo "System Installation:"
    echo "  Service file: $system_service"
    if [[ -f "$system_service" ]]; then
        print_message SUCCESS "Installed"
    else
        print_message WARNING "Not installed - run: sudo $SCRIPT_NAME --install -n $CONNECTOR_NAME"
    fi

    echo
    echo "  Sudo config: $system_sudoers"
    if [[ -f "$system_sudoers" ]]; then
        print_message SUCCESS "Installed"
    else
        print_message WARNING "Not installed"
    fi

    echo
    echo "Documentation: $readme"
    if [[ -f "$readme" ]]; then
        print_message SUCCESS "Exists"
    else
        print_message WARNING "Not found"
    fi

    # Show service status if installed
    if [[ -f "$system_service" ]]; then
        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        systemctl status "$SERVICE_NAME" --no-pager -l || true
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo

        if systemctl is-active "$SERVICE_NAME" &> /dev/null; then
            print_message SUCCESS "Service is installed and running"
        else
            print_message WARNING "Service is installed but not running"
        fi
    else
        echo
        print_message INFO "Service not installed to system yet"
    fi
}

# ------------------------------------------------------------------------------
# Function: uninstall_service
# Purpose.: Uninstall service from system (root)
# Args....: None
# Returns.: 0 on success
# Output..: Log messages
# ------------------------------------------------------------------------------
# Remove service from system (requires root)
uninstall_service() {
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    local system_service="/etc/systemd/system/$SERVICE_NAME"
    local system_sudoers="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"

    print_message STEP "Uninstalling service for connector: $CONNECTOR_NAME"
    echo

    if [[ ! -f "$system_service" ]]; then
        print_message WARNING "Service not installed: $SERVICE_NAME"
        return 0
    fi

    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - Would remove:"
        echo "  - $system_service"
        if [[ -f "$system_sudoers" ]]; then
            echo "  - $system_sudoers"
        fi
        return 0
    fi

    # Confirm removal
    if $INTERACTIVE; then
        local answer
        read -rp "Uninstall service $SERVICE_NAME? [y/N]: " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Uninstall cancelled"
            return 0
        fi
    fi

    # Stop service
    print_message INFO "Stopping service"
    systemctl stop "$SERVICE_NAME" 2> /dev/null || true

    # Disable service
    print_message INFO "Disabling service"
    systemctl disable "$SERVICE_NAME" 2> /dev/null || true

    # Remove files
    print_message INFO "Removing service files from system"
    rm -f "$system_service"
    [[ -f "$system_sudoers" ]] && rm -f "$system_sudoers"

    # Reload systemd
    print_message INFO "Reloading systemd daemon"
    systemctl daemon-reload

    print_message SUCCESS "Service uninstalled successfully"
    echo
    print_message INFO "Local configuration files preserved in: $CONNECTOR_ETC"
    print_message INFO "To reinstall: sudo $SCRIPT_NAME --install -n $CONNECTOR_NAME"
}

# ------------------------------------------------------------------------------
# Function: parse_arguments
# Purpose.: Parse command-line arguments
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Sets global flags and variables
# ------------------------------------------------------------------------------
# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prepare)
                PREPARE_MODE=true
                shift
                ;;
            --install)
                INSTALL_MODE=true
                shift
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -n | --connector)
                CONNECTOR_NAME="$2"
                shift 2
                ;;
            -b | --base)
                CONNECTOR_BASE="$2"
                shift 2
                ;;
            -u | --user)
                OS_USER="$2"
                shift 2
                ;;
            -g | --group)
                OS_GROUP="$2"
                shift 2
                ;;
            -j | --java-home)
                JAVA_HOME="$2"
                shift 2
                ;;
            -l | --list)
                LIST_MODE=true
                shift
                ;;
            -c | --check)
                CHECK_MODE=true
                shift
                ;;
            -t | --test)
                TEST_MODE=true
                DRY_RUN=true
                shift
                ;;
            --skip-sudo)
                SKIP_SUDO=true
                shift
                ;;
            --no-color)
                USE_COLOR=false
                shift
                ;;
            -y | --yes)
                INTERACTIVE=false
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v | --verbose)
                VERBOSE=true
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

    # Default to prepare mode if no mode specified
    if ! $PREPARE_MODE && ! $INSTALL_MODE && ! $UNINSTALL_MODE && ! $LIST_MODE && ! $CHECK_MODE; then
        PREPARE_MODE=true
    fi
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point
# Args....: $@ - All command-line arguments
# Returns.: 0 on success, exits on error
# Output..: Log messages
# ------------------------------------------------------------------------------
# Main function
main() {
    # Initialize colors
    init_colors

    # Parse arguments
    parse_arguments "$@"

    # Check root requirements
    check_root

    # Handle list mode
    if $LIST_MODE; then
        list_connectors
        exit 0
    fi

    # Interactive connector selection if not specified
    if [[ -z "$CONNECTOR_NAME" ]]; then
        if $INTERACTIVE; then
            select_connector_interactive
        else
            print_message ERROR "Connector name required in non-interactive mode"
            echo "Use --connector <name> or run without --yes for interactive mode"
            exit 1
        fi
    fi

    # Validate connector
    if ! validate_connector "$CONNECTOR_NAME" "$CONNECTOR_BASE"; then
        exit 1
    fi

    print_message SUCCESS "Connector validated: $CONNECTOR_NAME"
    $VERBOSE && print_message INFO "CMAN instance detected: $CMAN_NAME"

    # Handle different modes
    if $CHECK_MODE; then
        check_service
    elif $UNINSTALL_MODE; then
        uninstall_service
    elif $INSTALL_MODE; then
        install_service
    elif $PREPARE_MODE; then
        prepare_service
    fi
}

# ------------------------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------------------------
main "$@"
# - EOF ------------------------------------------------------------------------
