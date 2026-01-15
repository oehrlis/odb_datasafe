#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: install_datasafe_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.01.11
# Version....: v1.0.0
# Purpose....: Install and manage Oracle Data Safe On-Premises Connector as systemd service
#              Generic solution for any connector with automatic discovery and configuration
# Notes......: Must be run as root. Supports multiple connectors per server.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.11 oehrli - initial version with auto-discovery and interactive mode
# ------------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------------------
# Default Configuration
# ------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="v1.0.0"

# Default paths (can be overridden)
DEFAULT_CONNECTOR_BASE="/appl/oracle/product/dsconnect"
DEFAULT_USER="oracle"
DEFAULT_GROUP="dba"
DEFAULT_JAVA_HOME="/appl/oracle/product/dsconnect/jdk"

# Runtime variables
CONNECTOR_BASE="${CONNECTOR_BASE:-$DEFAULT_CONNECTOR_BASE}"
CONNECTOR_NAME=""
CONNECTOR_HOME=""
CMAN_NAME=""
CMAN_HOME=""
CMAN_CTL=""
OS_USER="${OS_USER:-$DEFAULT_USER}"
OS_GROUP="${OS_GROUP:-$DEFAULT_GROUP}"
JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"

# Mode flags
DRY_RUN=false
TEST_MODE=false
INTERACTIVE=true
LIST_MODE=false
REMOVE_MODE=false
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

# Print colored message
print_message() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        ERROR) echo -e "${RED}❌ ERROR:${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}✅${NC} $message" ;;
        WARNING) echo -e "${YELLOW}⚠️  WARNING:${NC} $message" ;;
        INFO) echo -e "${BLUE}ℹ️${NC}  $message" ;;
        STEP) echo -e "${BOLD}▶${NC}  $message" ;;
        *) echo "$message" ;;
    esac
}

# Usage information
usage() {
    cat << EOF
${BOLD}Oracle Data Safe Service Installer${NC}
Version: $SCRIPT_VERSION

${BOLD}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${BOLD}Description:${NC}
    Install Oracle Data Safe On-Premises Connector as a systemd service.
    Supports multiple connectors per server with automatic configuration.
t, --test                Test/demo mode (works without root, shows what would happen)
        --skip-sudo           Skip sudo configuration (useful for testing environments)
        --no-color            Disable colored output
    -
${BOLD}Options:${NC}
    -n, --connector <name>    Connector name (directory name under base path)
    -b, --base <path>         Connector base directory (default: $DEFAULT_CONNECTOR_BASE)
    -u, --user <user>         OS user for service (default: $DEFAULT_USER)
    -g, --group <group>       OS group for service (default: $DEFAULT_GROUP)
    -j, --java-home <path>    JAVA_HOME path (default: $DEFAULT_JAVA_HOME)
    
    -l, --list                List all available connectors
    -c, --check               Check if service is installed for connector
    -r, --remove              Remove service and sudo configuration
    
    -y, --yes                 Non-interactive mode (use defaults/provided values)
    -d, --dry-run             Show what would be done without making changes
    -v, --verbose             Verbose output
    -h, --help                Show this help message

${BOLD}Examples:${NC}
    # List available connectors
    $SCRIPT_NAME --list

    # Interactive installation (prompts for connector selection)
    $SCRIPT_NAME

    # Non-interactive installation for  (requires root)
    $SCRIPT_NAME -n my-connector --dry-run

    # Test/demo mode (works without root)
    $SCRIPT_NAME -n my-connector --test

    # Check if service is installed
    $SCRIPT_NAME -n my-connector --check

    # Remove service
    $SCRIPT_NAME -n my-connector --remove

    # Custom configuration
    $SCRIPT_NAME -n my-connector -u oracle -g dba -j /opt/java/jdk

    # Install without sudo config (for environments with external sudo management)
    $SCRIPT_NAME -n my-connector --skip-sudo -y

    # Custom configuration
    $SCRIPT_NAME -n my-connector -u oracle -g dba -j /opt/java/jdk

${BOLD}Environment Variables:${NC}
    CONNECTOR_BASE            Override default connector base path
    OS_USER                   Override default OS user
    OS_GROUP                  Override default OS group
    JAVA_HOME                 Override default Java home

${BOLD}Notes:${NC}
    - Must be run as root
    - Connectors must be in: \$CONNECTOR_BASE/<connector-name>/
    - Each connector gets a unique service: oracle_datasafe_<connector-name>.service
    - Auto-detects CMAN instance name from cman.ora
    - Generates sudo config for specified user to manage service

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Check if running as root (unless in dry-run or test mode)
# ------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        if $DRY_RUN || $TEST_MODE; then
            print_message WARNING "Not running as root (dry-run/test mode)"
            return 0
        fi
        print_message ERROR "This script must be run as root"
        print_message INFO "Tip: Use --dry-run or --test mode to preview without root access"
        exit 1
    fi
}

# Discover available connectors
discover_connectors() {
    local base="$1"
    local -a connectors=()

    if [[ ! -d "$base" ]]; then
        print_message ERROR "Connector base directory not found: $base"
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

        printf "%2d. %-50s %s\n" "$idx" "$connector" "$installed"
        printf "    Path: %s\n" "$conn_path"

        # Try to get CMAN name from cman.ora
        local cman_ora="$cman_home/network/admin/cman.ora"
        if [[ -f "$cman_ora" ]]; then
            local cman_name
            cman_name="$(grep -E '^\s*[A-Za-z0-9_]+\s*=' "$cman_ora" 2> /dev/null | head -1 | awk -F= '{print $1}' | tr -d ' ' || echo "N/A")"
            printf "    CMAN: %s\n" "$cman_name"
        fi
        echo
        ((idx++))
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#connectors[@]} connector(s) found"
}

# Validate connector directory
validate_connector() {
    local connector="$1"
    local base="$2"

    CONNECTOR_HOME="$base/$connector"

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

    # Validate user and group (skip in test mode or dry-run)
    if ! $TEST_MODE && ! $DRY_RUN; then
        if ! id "$OS_USER" &> /dev/null; then
            print_message ERROR "User does not exist: $OS_USER"
            return 1
        fi

        if ! getent group "$OS_GROUP" &> /dev/null; then
            print_message ERROR "Group does not exist: $OS_GROUP"
            return 1
        fi
    fi

    return 0
}

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
        ((idx++))
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

- **Service file**: /etc/systemd/system/$SERVICE_NAME
- **Sudo config**: /etc/sudoers.d/$OS_USER-datasafe-$CONNECTOR_NAME
- **CMAN config**: $CMAN_HOME/network/admin/cman.ora
- **This README**: $README_FILE

## Uninstallation

To remove this service:
\`\`\`bash
sudo $SCRIPT_NAME --connector $CONNECTOR_NAME --remove
\`\`\`

---
Generated by $SCRIPT_NAME $SCRIPT_VERSION
EOF

    chmod 644 "$readme"
}

# Install service
install_service() {
    print_message STEP "Installing Data Safe Connector Service"
    echo

    # Set service and file names
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    SUDOERS_FILE="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    README_FILE="$CONNECTOR_HOME/SERVICE_README.md"

    # Check if already installed
    if [[ -f "$SERVICE_FILE" ]] && ! $DRY_RUN; then
        local answer
        read -rp "Service already installed. Overwrite? [y/N]: " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Installation cancelled"
            return 0
        fi
        # Stop existing service
        systemctl stop "$SERVICE_NAME" 2> /dev/null || true
    fi

    # Display configuration
    echo "Configuration:"
    echo "  Connector Name....: $CONNECTOR_NAME"
    echo "  Connector Home....: $CONNECTOR_HOME"
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
    print_message INFO "Creating systemd service file: $SERVICE_FILE"
    generate_service_file > "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"

    # Create sudoers file (unless skipped)
    if ! $SKIP_SUDO; then
        print_message INFO "Creating sudoers configuration: $SUDOERS_FILE"
        generate_sudoers_file > "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"

        # Validate sudoers syntax
        if ! visudo -c -f "$SUDOERS_FILE" &> /dev/null; then
            print_message ERROR "Invalid sudoers syntax, removing file"
            rm -f "$SUDOERS_FILE"
            return 1
        fi
    else
        print_message INFO "Skipping sudoers configuration (--skip-sudo)"
    fi

    # Generate README
    print_message INFO "Creating service documentation: $README_FILE"
    generate_readme

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
    print_message SUCCESS "Data Safe Connector Service Installation Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Service Name: $SERVICE_NAME"
    echo "User: $OS_USER (with sudo privileges configured)"
    echo
    echo "${BOLD}Quick Commands for $OS_USER:${NC}"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl restart $SERVICE_NAME"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
    echo
    echo "${BOLD}Documentation:${NC}"
    echo "  $README_FILE"
    echo
    echo "${BOLD}Configuration Files:${NC}"
    echo "  Service: $SERVICE_FILE"
    echo "  Sudo:    $SUDOERS_FILE"
    echo
}

# Check service status
check_service() {
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    SUDOERS_FILE="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    README_FILE="$CONNECTOR_HOME/SERVICE_README.md"

    echo
    print_message STEP "Checking service installation for connector: $CONNECTOR_NAME"
    echo

    local installed=true

    # Check service file
    echo "Service file: $SERVICE_FILE"
    if [[ -f "$SERVICE_FILE" ]]; then
        print_message SUCCESS "Exists"
    else
        print_message ERROR "Not found"
        installed=false
    fi

    # Check sudoers file
    echo
    echo "Sudoers file: $SUDOERS_FILE"
    if [[ -f "$SUDOERS_FILE" ]]; then
        print_message SUCCESS "Exists"
    else
        print_message ERROR "Not found"
        installed=false
    fi

    # Check README
    echo
    echo "Documentation: $README_FILE"
    if [[ -f "$README_FILE" ]]; then
        print_message SUCCESS "Exists"
    else
        print_message WARNING "Not found"
    fi

    echo
    if $installed; then
        # Show service status
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
        print_message ERROR "Service is not installed"
        return 1
    fi
}

# Remove service
remove_service() {
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    SUDOERS_FILE="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"
    README_FILE="$CONNECTOR_HOME/SERVICE_README.md"

    print_message STEP "Removing service for connector: $CONNECTOR_NAME"
    echo

    if [[ ! -f "$SERVICE_FILE" ]]; then
        print_message WARNING "Service not installed: $SERVICE_NAME"
        return 0
    fi

    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - Would remove:"
        echo "  - $SERVICE_FILE"
        echo "  - $SUDOERS_FILE"
        echo "  - $README_FILE"
        return 0
    fi

    # Confirm removal
    if $INTERACTIVE; then
        local answer
        read -rp "Remove service $SERVICE_NAME? [y/N]: " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            print_message INFO "Removal cancelled"
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
    print_message INFO "Removing service files"
    rm -f "$SERVICE_FILE"
    rm -f "$SUDOERS_FILE"
    rm -f "$README_FILE"

    # Reload systemd
    print_message INFO "Reloading systemd daemon"
    systemctl daemon-reload

    print_message SUCCESS "Service removed successfully"
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            -r | --remove)
                REMOVE_MODE=true
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
}

# Main function
main() {
    # Initialize colors
    init_colors

    # Parse arguments
    parse_arguments "$@"

    # Check root
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
    elif $REMOVE_MODE; then
        remove_service
    else
        install_service
    fi
}

# ------------------------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------------------------
main "$@"
# - EOF ------------------------------------------------------------------------
