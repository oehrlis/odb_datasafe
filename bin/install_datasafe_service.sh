#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: install_datasafe_service.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.06.25
# Version....: v1.0.1
# Purpose....: Install and manage Oracle Data Safe On-Premises Connector as systemd service
#              Generic solution for any connector with automatic discovery and configuration
# Notes......: Works as regular user for config preparation. Root only for system installation.
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------
# Modified...:
# 2026.01.11 oehrli - initial version with auto-discovery and interactive mode
# 2026.01.21 oehrli - refactored to allow non-root config generation
# 2026.06.25 oehrli - integrate oradba_dsctl.sh for ExecStart/Stop/Reload
# ------------------------------------------------------------------------------

set -euo pipefail

# Minimal ERR/EXIT traps (standalone installer — does not source lib/common.sh)
_installer_error_handler() {
    local rc=$1 line=$2 cmd=$3
    echo "ERROR: installer failed (exit $rc) at line $line: $cmd" >&2
    exit "$rc"
}
trap '_installer_error_handler $? $LINENO "$BASH_COMMAND"' ERR
trap 'exit $?' EXIT

# ------------------------------------------------------------------------------
# Default Configuration
# ------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="v1.0.2"

# Default paths (can be overridden)
DEFAULT_CONNECTOR_BASE="${ORACLE_BASE:-/u01/app/oracle}/product"
DEFAULT_USER="$(id -un)"
DEFAULT_GROUP="dba"
DEFAULT_JAVA_HOME="${ORACLE_BASE:-/u01/app/oracle}/product/jdk"
ORADBA_BASE="${ORADBA_BASE:-${ORADBA_PREFIX:-/opt/oradba}}"

# Runtime variables
CONNECTOR_BASE="${CONNECTOR_BASE:-$DEFAULT_CONNECTOR_BASE}"
CONNECTOR_NAME=""
CONNECTOR_HOME=""
CONNECTOR_ETC=""
CMAN_NAME=""
CMAN_HOME=""
CMAN_CTL=""
REGISTRY_ALIAS=""
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
ALL_MODE=false

# Service configuration
SERVICE_NAME=""
SERVICE_FILE=""
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
        SUCCESS) echo -e "${GREEN}[OK]${NC} $message" >&2 ;;
        WARNING) echo -e "${YELLOW}[WARNING]:${NC} $message" >&2 ;;
        INFO) echo -e "${BLUE}[INFO]${NC}  $message" >&2 ;;
        STEP) echo -e "${BOLD}▶${NC}  $message" >&2 ;;
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
    --all                   Process all discovered connectors (combine with --prepare/--install/--uninstall)
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

  # Process all connectors (prepare or install)
  $SCRIPT_NAME --prepare --all
  sudo $SCRIPT_NAME --install --all

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
# Function: find_connector_base
# Purpose.: Discover connector base path when ORACLE_BASE is not set
# Args....: $1 - Connector name
# Returns.: 0 on success (prints base path), 1 if not found
# Output..: Connector base path to stdout
# ------------------------------------------------------------------------------
find_connector_base() {
    local connector="$1"
    local base
    local -a candidates=(
        "${ORACLE_BASE:+${ORACLE_BASE}/product}"
        "/appl/oracle/product"
        "/u01/app/oracle/product"
        "/u01/oracle/product"
        "/opt/oracle/product"
    )
    for base in "${candidates[@]+"${candidates[@]}"}"; do
        [[ -z "${base}" ]] && continue
        if [[ -d "${base}/${connector}/oracle_cman_home" ]]; then
            echo "${base}"
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------------------
# Function: resolve_install_context
# Purpose.: Minimal context resolution for install/uninstall/check modes.
#           Does NOT validate JAVA_HOME, CMAN_HOME, or cmctl — those are
#           already embedded in the prepared service file.
# Args....: $1 - mode: install | uninstall | check
# Returns.: 0 on success, 1 on error
# Output..: Sets CONNECTOR_HOME, CONNECTOR_ETC, SERVICE_NAME, OS_USER, OS_GROUP
# ------------------------------------------------------------------------------
resolve_install_context() {
    local mode="${1:-install}"

    # Auto-discover base only if still at default and directory missing
    if [[ "${CONNECTOR_BASE}" == "${DEFAULT_CONNECTOR_BASE}" ]] && [[ ! -d "${CONNECTOR_BASE}/${CONNECTOR_NAME}" ]]; then
        local discovered_base
        if discovered_base=$(find_connector_base "${CONNECTOR_NAME}"); then
            print_message INFO "Auto-discovered connector base: ${discovered_base}"
            CONNECTOR_BASE="${discovered_base}"
        fi
    fi

    CONNECTOR_HOME="${CONNECTOR_BASE}/${CONNECTOR_NAME}"
    CONNECTOR_ETC="${CONNECTOR_HOME}/etc/systemd"
    SERVICE_NAME="oracle_datasafe_${CONNECTOR_NAME}.service"

    if [[ ! -d "${CONNECTOR_HOME}" ]]; then
        print_message ERROR "Connector directory not found: ${CONNECTOR_HOME}"
        print_message INFO "Use --base or set ORACLE_BASE to point to the connector base"
        return 1
    fi

    local prepared_file="${CONNECTOR_ETC}/${SERVICE_NAME}"
    local installed_file="/etc/systemd/system/${SERVICE_NAME}"

    if [[ "${mode}" == "install" ]]; then
        # Require the prepared file to exist — no auto-regeneration
        if [[ ! -f "${prepared_file}" ]]; then
            print_message ERROR "Prepared service file not found: ${prepared_file}"
            print_message INFO "Run first as oracle user: ${SCRIPT_NAME} --prepare -n ${CONNECTOR_NAME}"
            return 1
        fi
        # Read OS_USER / OS_GROUP from the prepared file, or warn if explicitly overridden
        local raw_user raw_group file_user="" file_group=""
        raw_user=$(grep -E '^User=' "${prepared_file}" 2> /dev/null | head -1 || true)
        [[ -n "${raw_user}" ]] && file_user="${raw_user#User=}"
        raw_group=$(grep -E '^Group=' "${prepared_file}" 2> /dev/null | head -1 || true)
        [[ -n "${raw_group}" ]] && file_group="${raw_group#Group=}"

        if [[ "${OS_USER}" == "${DEFAULT_USER}" ]]; then
            [[ -n "${file_user}" ]] && OS_USER="${file_user}" \
                && print_message INFO "OS user from prepared service file: ${OS_USER}"
        elif [[ -n "${file_user}" ]] && [[ "${file_user}" != "${OS_USER}" ]]; then
            print_message WARNING "Prepared service has User=${file_user} but --user ${OS_USER} was given"
            print_message INFO "Service will run as ${file_user}. Re-run --prepare -n ${CONNECTOR_NAME} --user ${OS_USER} to change."
        fi

        if [[ "${OS_GROUP}" == "${DEFAULT_GROUP}" ]]; then
            [[ -n "${file_group}" ]] && OS_GROUP="${file_group}" \
                && print_message INFO "OS group from prepared service file: ${OS_GROUP}"
        elif [[ -n "${file_group}" ]] && [[ "${file_group}" != "${OS_GROUP}" ]]; then
            print_message WARNING "Prepared service has Group=${file_group} but --group ${OS_GROUP} was given"
        fi

    elif [[ "${mode}" == "uninstall" ]]; then
        # Read OS_USER from the installed system service file for correct sudoers filename
        if [[ -f "${installed_file}" ]] && [[ "${OS_USER}" == "${DEFAULT_USER}" ]]; then
            local raw_user
            raw_user=$(grep -E '^User=' "${installed_file}" 2> /dev/null | head -1 || true)
            if [[ -n "${raw_user}" ]]; then
                OS_USER="${raw_user#User=}"
                print_message INFO "OS user from installed service file: ${OS_USER}"
            fi
        fi
    fi
    # check mode: paths are set; existence of files is reported by check_service, not here

    return 0
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
# Function: lookup_registry_alias
# Purpose.: Look up registry alias for a connector directory name
# Args....: $1 - Connector directory name (e.g. exacc-wob-vwg-ha1)
#           $2 - ORADBA_BASE path
# Returns.: 0 on success (alias found), 1 on error
# Output..: Registry alias to stdout
# ------------------------------------------------------------------------------
lookup_registry_alias() {
    local connector_dir="$1"
    local oradba_base="$2"
    local homes_conf="${oradba_base}/etc/oradba_homes.conf"
    local connector_home="${CONNECTOR_BASE}/${connector_dir}"

    if [[ ! -f "${homes_conf}" ]]; then
        print_message WARNING "oradba_homes.conf not found: ${homes_conf}"
        return 1
    fi

    local alias
    alias=$(grep -v '^#' "${homes_conf}" | awk -F: -v home="${connector_home}" '$2 == home {print $1}' | head -1)

    if [[ -z "${alias}" ]]; then
        print_message WARNING "No registry alias found for ${connector_home} in ${homes_conf}"
        return 1
    fi

    echo "${alias}"
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
EOF

    if [[ -n "${REGISTRY_ALIAS:-}" ]]; then
        printf 'Type=oneshot\n'
        printf 'RemainAfterExit=yes\n'
    else
        printf 'Type=forking\n'
    fi

    cat << EOF
User=$OS_USER
Group=$OS_GROUP

# Environment
Environment="JAVA_HOME=$JAVA_HOME"
Environment="ORACLE_HOME=$CMAN_HOME"
Environment="PATH=$JAVA_HOME/bin:$CMAN_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Working directory
WorkingDirectory=$CONNECTOR_HOME

# Service management
EOF

    if [[ -n "${REGISTRY_ALIAS:-}" ]]; then
        local dsctl="${ORADBA_BASE}/bin/oradba_dsctl.sh"
        cat << EOF
Environment="ORADBA_LOG=${CONNECTOR_HOME}/log"
ExecStart=${dsctl} start ${REGISTRY_ALIAS}
ExecStop=${dsctl} stop ${REGISTRY_ALIAS}
ExecReload=${dsctl} restart ${REGISTRY_ALIAS}
EOF
    else
        cat << EOF
ExecStart=$CMAN_CTL startup -c $CMAN_NAME
ExecStop=$CMAN_CTL shutdown -c $CMAN_NAME
ExecReload=$CMAN_CTL restart -c $CMAN_NAME
EOF
    fi

    cat << EOF

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
# Purpose.: Generate consolidated sudoers content for all Data Safe connectors
# Args....: None
# Returns.: 0 on success
# Output..: Sudoers file content to stdout
# ------------------------------------------------------------------------------
generate_sudoers_file() {
    local systemctl_bin
    systemctl_bin=$(command -v systemctl 2> /dev/null || echo "/usr/bin/systemctl")
    local odb_bin
    odb_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cat << EOF
# ------------------------------------------------------------------------------
# Sudo configuration for Oracle Data Safe On-Premises Connectors
# Generated: $(date)
# Managed by: $SCRIPT_NAME $SCRIPT_VERSION
# Grants $OS_USER permission to manage all oracle_datasafe_* services
# and to run the install/uninstall scripts.
# ------------------------------------------------------------------------------
Cmnd_Alias ORADBA_DATASAFE_CTL = \\
    ${systemctl_bin} start   oracle_datasafe_*.service, \\
    ${systemctl_bin} stop    oracle_datasafe_*.service, \\
    ${systemctl_bin} restart oracle_datasafe_*.service, \\
    ${systemctl_bin} reload  oracle_datasafe_*.service, \\
    ${systemctl_bin} enable  oracle_datasafe_*.service, \\
    ${systemctl_bin} disable oracle_datasafe_*.service

Cmnd_Alias ORADBA_DATASAFE_ADMIN = \\
    ${odb_bin}/install_datasafe_service.sh, \\
    ${odb_bin}/uninstall_all_datasafe_services.sh

${OS_USER} ALL=(root) NOPASSWD: ORADBA_DATASAFE_CTL
${OS_USER} ALL=(root) NOPASSWD: ORADBA_DATASAFE_ADMIN
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
- **Sudo config (system)**: /etc/sudoers.d/oradba-datasafe (shared, covers all connectors)
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
    README_FILE="$CONNECTOR_HOME/SERVICE_README.md"

    # Ensure etc directory exists
    if [[ ! -d "$CONNECTOR_ETC" ]]; then
        mkdir -p "$CONNECTOR_ETC" || {
            print_message ERROR "Cannot create directory: $CONNECTOR_ETC"
            return 1
        }
    fi

    # Look up registry alias for oradba_dsctl.sh integration
    REGISTRY_ALIAS=""
    if REGISTRY_ALIAS=$(lookup_registry_alias "${CONNECTOR_NAME}" "${ORADBA_BASE}"); then
        print_message INFO "Registry alias resolved: ${REGISTRY_ALIAS} -> ${CONNECTOR_NAME}"
        # DEP-007: hard error if dsctl binary is absent when a registry alias is resolved
        local dsctl_bin="${ORADBA_BASE}/bin/oradba_dsctl.sh"
        if [[ ! -x "${dsctl_bin}" ]]; then
            print_message ERROR "oradba_dsctl.sh not found or not executable: ${dsctl_bin}"
            print_message INFO "Set ORADBA_BASE to the correct path and retry --prepare"
            return 1
        fi
    else
        print_message WARNING "Falling back to direct cmctl calls (no registry alias found)"
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
        echo "  - $README_FILE"
        if ! $SKIP_SUDO; then
            echo "  - /etc/sudoers.d/oradba-datasafe (installed at --install step)"
        fi
        echo
        echo "Service file content:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        generate_service_file
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ! $SKIP_SUDO; then
            echo
            echo "Consolidated sudoers content (/etc/sudoers.d/oradba-datasafe):"
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

    if ! $SKIP_SUDO; then
        print_message INFO "Consolidated sudoers will be installed at: /etc/sudoers.d/oradba-datasafe (--install step)"
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
        echo "  Sudoers: to be installed at /etc/sudoers.d/oradba-datasafe (--install step)"
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
    local system_service="/etc/systemd/system/$SERVICE_NAME"
    local system_sudoers="/etc/sudoers.d/oradba-datasafe"
    local legacy_sudoers_glob="/etc/sudoers.d/${OS_USER}-datasafe-*"

    # Safety net: prepared file must exist (already verified by resolve_install_context)
    if [[ ! -f "$local_service" ]]; then
        print_message ERROR "Service file not found: $local_service"
        print_message INFO "Run first as oracle user: $SCRIPT_NAME --prepare -n $CONNECTOR_NAME"
        return 1
    fi

    # Validate ExecStart executable exists (catches wrong ORADBA_BASE paths)
    local raw_exec exec_bin=""
    raw_exec=$(grep -E '^ExecStart=' "${local_service}" 2> /dev/null | head -1 || true)
    if [[ -n "${raw_exec}" ]]; then
        exec_bin="${raw_exec#ExecStart=}"
        exec_bin="${exec_bin%% *}"
    fi
    if [[ -n "${exec_bin}" ]] && [[ ! -x "${exec_bin}" ]]; then
        print_message WARNING "ExecStart binary not found or not executable: ${exec_bin}"
        print_message INFO "If using oradba_dsctl.sh: set ORADBA_BASE and re-run --prepare"
        print_message INFO "  ORADBA_BASE=/correct/path $SCRIPT_NAME --prepare -n $CONNECTOR_NAME"
    fi

    # Display what will be installed
    echo "Installation plan:"
    echo "  Source........: $CONNECTOR_ETC"
    echo "  Service file..: $local_service"
    echo "               -> $system_service"
    echo "  Service User..: ${OS_USER}"
    if [[ -n "${exec_bin}" ]]; then
        echo "  ExecStart.....: ${exec_bin}"
    fi
    if ! $SKIP_SUDO; then
        if [[ -f "$system_sudoers" ]]; then
            echo "  Sudo config...: $system_sudoers (already installed - will skip)"
        else
            echo "  Sudo config...: $system_sudoers (will install)"
            echo "  Legacy cleanup: ${legacy_sudoers_glob} (will remove if present)"
        fi
    fi
    echo

    # Handle dry-run
    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - No changes will be made"
        echo
        echo "Would execute:"
        echo "  1. Copy $local_service to $system_service"
        if ! $SKIP_SUDO; then
            echo "  2. Remove legacy sudoers: ${legacy_sudoers_glob}"
            if [[ -f "$system_sudoers" ]]; then
                echo "  3. Skip sudoers install (already present): $system_sudoers"
            else
                echo "  3. Validate and install: $system_sudoers"
                echo "     Content:"
                generate_sudoers_file | sed 's/^/     /'
            fi
        fi
        local log_dir_dry="${CONNECTOR_HOME}/log"
        if [[ ! -d "${log_dir_dry}" ]]; then
            print_message INFO "Creating connector log directory: ${log_dir_dry}"
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

    # Ensure connector log directory exists (required by oradba_dsctl.sh)
    local log_dir="${CONNECTOR_HOME}/log"
    if [[ ! -d "${log_dir}" ]]; then
        print_message INFO "Creating connector log directory: ${log_dir}"
        mkdir -p "${log_dir}"
        chown "${OS_USER}:${OS_GROUP}" "${log_dir}"
    fi

    # Copy service file
    print_message INFO "Installing service file to: $system_service"
    cp "$local_service" "$system_service"
    chmod 644 "$system_service"

    # Install consolidated sudoers (unless skipped)
    if ! $SKIP_SUDO; then
        # Remove legacy per-connector sudoers files first
        local f
        for f in "/etc/sudoers.d/${OS_USER}"-datasafe-*; do
            [[ -f "$f" ]] || continue
            print_message INFO "Removing legacy sudoers file: $f"
            rm -f "$f"
        done

        if [[ -f "$system_sudoers" ]]; then
            print_message INFO "Consolidated sudoers already present, skipping: $system_sudoers"
        else
            local tmp_sudoers
            tmp_sudoers=$(mktemp)
            generate_sudoers_file > "$tmp_sudoers"
            if ! visudo -cf "$tmp_sudoers" > /dev/null 2>&1; then
                print_message ERROR "Sudoers syntax validation failed; aborting install" >&2
                rm -f "$tmp_sudoers"
                return 1
            fi
            install -m 0440 -o root -g root "$tmp_sudoers" "$system_sudoers"
            rm -f "$tmp_sudoers"
            print_message SUCCESS "Consolidated sudoers installed: $system_sudoers"
        fi
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
    local system_service="/etc/systemd/system/$SERVICE_NAME"
    local system_sudoers="/etc/sudoers.d/oradba-datasafe"
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
# Function: stop_service
# Purpose.: Stop a connector service, preferring oradba_dsctl.sh if available
# Args....: $1 - systemd service name
# Returns.: 0 always (errors are non-fatal)
# Output..: Log messages
# ------------------------------------------------------------------------------
stop_service() {
    local service="$1"
    local connector_name="${service#oracle_datasafe_}"
    connector_name="${connector_name%.service}"
    local cman_bin="${CONNECTOR_BASE}/${connector_name}/oracle_cman_home/bin"

    local dsctl="${ORADBA_BASE}/bin/oradba_dsctl.sh"
    if [[ -x "${dsctl}" ]]; then
        local alias
        if alias=$(lookup_registry_alias "${connector_name}" "${ORADBA_BASE}"); then
            print_message INFO "Stopping via oradba_dsctl.sh stop ${alias}"
            "${dsctl}" stop "${alias}" 2> /dev/null || true
            # Verify process actually stopped; fall through to pkill if still running
            local status_check
            status_check=$("${dsctl}" status "${alias}" 2> /dev/null || true)
            if [[ -n "${status_check}" && "${status_check}" != *"RUNNING"* ]]; then
                return 0
            fi
            print_message WARNING "Process still running after dsctl stop - forcing via pkill"
        fi
    else
        # No dsctl: rely on systemctl stop
        print_message INFO "Stopping via systemctl"
        systemctl stop "${service}" 2> /dev/null || true
    fi

    # Force-kill remaining CMAN processes if directory is reachable
    if [[ -d "${cman_bin}" ]]; then
        if pgrep -f "${cman_bin}/" > /dev/null 2>&1; then
            print_message INFO "Force-killing remaining CMAN processes"
            pkill -f "${cman_bin}/" 2> /dev/null || true
        fi
    fi
    return 0
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
    local legacy_sudoers="/etc/sudoers.d/${OS_USER}-datasafe-${CONNECTOR_NAME}"

    print_message STEP "Uninstalling service for connector: $CONNECTOR_NAME"
    echo

    if [[ ! -f "$system_service" ]]; then
        print_message WARNING "Service not installed: $SERVICE_NAME"
        return 0
    fi

    if $DRY_RUN; then
        print_message INFO "DRY-RUN MODE - Would remove:"
        echo "  - $system_service"
        if [[ -f "$legacy_sudoers" ]]; then
            echo "  - $legacy_sudoers (legacy per-connector sudoers)"
        fi
        print_message INFO "Shared sudoers /etc/sudoers.d/oradba-datasafe is retained (covers all connectors)"
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

    # Stop and disable service (with oradba_dsctl.sh integration if available)
    stop_service "${SERVICE_NAME}"

    print_message INFO "Disabling service"
    systemctl disable "$SERVICE_NAME" 2> /dev/null || true

    # Remove service file and any legacy per-connector sudoers
    print_message INFO "Removing service files from system"
    rm -f "$system_service"
    if [[ -f "$legacy_sudoers" ]]; then
        print_message INFO "Removing legacy sudoers file: $legacy_sudoers"
        rm -f "$legacy_sudoers"
    fi
    print_message INFO "Shared sudoers /etc/sudoers.d/oradba-datasafe retained (covers all connectors)"

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
            --all)
                ALL_MODE=true
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

    # --all and -n are mutually exclusive
    if $ALL_MODE && [[ -n "${CONNECTOR_NAME}" ]]; then
        print_message ERROR "--all and --connector (-n) are mutually exclusive"
        echo "Use either --all or -n <name>, not both"
        exit 1
    fi

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

    # --all: batch mode — discover and process every connector in the base
    if $ALL_MODE; then
        # Establish base for batch discovery when still at default and missing
        if [[ "${CONNECTOR_BASE}" == "${DEFAULT_CONNECTOR_BASE}" ]] && [[ ! -d "${CONNECTOR_BASE}" ]]; then
            local -a _base_cands=(
                "${ORACLE_BASE:+${ORACLE_BASE}/product}"
                "/appl/oracle/product"
                "/u01/app/oracle/product"
                "/u01/oracle/product"
                "/opt/oracle/product"
            )
            local _cand
            for _cand in "${_base_cands[@]+"${_base_cands[@]}"}"; do
                [[ -z "${_cand}" ]] && continue
                if [[ -d "${_cand}" ]]; then
                    CONNECTOR_BASE="${_cand}"
                    print_message INFO "Using connector base for --all: ${CONNECTOR_BASE}"
                    break
                fi
            done
        fi

        local -a _all_connectors
        mapfile -t _all_connectors < <(discover_connectors "${CONNECTOR_BASE}")

        if [[ ${#_all_connectors[@]} -eq 0 ]]; then
            print_message ERROR "No connectors found in ${CONNECTOR_BASE}"
            exit 1
        fi

        print_message INFO "Found ${#_all_connectors[@]} connector(s) in ${CONNECTOR_BASE}"
        INTERACTIVE=false

        # Save CLI-provided user/group so each iteration can reset correctly
        local _user_init="${OS_USER}"
        local _group_init="${OS_GROUP}"
        local -a _ok_list=()
        local -a _fail_list=()

        for _conn in "${_all_connectors[@]}"; do
            echo
            print_message STEP "Processing connector: ${_conn}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            # Reset per-connector globals
            CONNECTOR_NAME="${_conn}"
            CONNECTOR_HOME=""
            CONNECTOR_ETC=""
            CMAN_NAME=""
            CMAN_HOME=""
            CMAN_CTL=""
            SERVICE_NAME=""
            OS_USER="${_user_init}"
            OS_GROUP="${_group_init}"

            local _conn_ok=0
            if $INSTALL_MODE; then
                if resolve_install_context "install" && install_service; then :; else _conn_ok=1; fi
            elif $UNINSTALL_MODE; then
                if resolve_install_context "uninstall" && uninstall_service; then :; else _conn_ok=1; fi
            elif $CHECK_MODE; then
                if resolve_install_context "check"; then check_service || true; else _conn_ok=1; fi
            elif $PREPARE_MODE; then
                if validate_connector "${_conn}" "${CONNECTOR_BASE}" && prepare_service; then :; else _conn_ok=1; fi
            fi

            if [[ "${_conn_ok}" -eq 0 ]]; then
                _ok_list+=("${_conn}")
            else
                _fail_list+=("${_conn}")
            fi
        done

        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_message STEP "Batch Summary (${CONNECTOR_BASE})"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        for _c in "${_ok_list[@]+"${_ok_list[@]}"}"; do
            print_message SUCCESS "${_c}"
        done
        for _c in "${_fail_list[@]+"${_fail_list[@]}"}"; do
            print_message ERROR "${_c} (FAILED)"
        done
        echo
        print_message INFO "Total: ${#_all_connectors[@]}  OK: ${#_ok_list[@]}  FAILED: ${#_fail_list[@]}"
        [[ ${#_fail_list[@]} -eq 0 ]] || exit 1
        exit 0
    fi

    # Single connector: interactive selection if not specified
    if [[ -z "$CONNECTOR_NAME" ]]; then
        if $INTERACTIVE; then
            select_connector_interactive
        else
            print_message ERROR "Connector name required in non-interactive mode"
            echo "Use --connector <name>, --all, or run without --yes for interactive mode"
            exit 1
        fi
    fi

    # Single connector: route by mode
    if $INSTALL_MODE || $UNINSTALL_MODE; then
        local _mode="install"
        $UNINSTALL_MODE && _mode="uninstall"
        if ! resolve_install_context "${_mode}"; then
            exit 1
        fi
        print_message SUCCESS "Install context resolved: ${CONNECTOR_NAME}"
    elif $CHECK_MODE; then
        if ! resolve_install_context "check"; then
            exit 1
        fi
    else
        # PREPARE_MODE: full validation including JAVA_HOME and CMAN checks
        if [[ "${CONNECTOR_BASE}" == "${DEFAULT_CONNECTOR_BASE}" ]] && [[ ! -d "${CONNECTOR_BASE}/${CONNECTOR_NAME}" ]]; then
            local discovered_base
            if discovered_base=$(find_connector_base "${CONNECTOR_NAME}"); then
                print_message INFO "Auto-discovered connector base: ${discovered_base}"
                CONNECTOR_BASE="${discovered_base}"
            fi
        fi
        if ! validate_connector "$CONNECTOR_NAME" "$CONNECTOR_BASE"; then
            exit 1
        fi
        print_message SUCCESS "Connector validated: $CONNECTOR_NAME"
        $VERBOSE && print_message INFO "CMAN instance detected: $CMAN_NAME"
    fi

    # Execute
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
