# GitHub Copilot Instructions for OraDBA Data Safe Extension

## Project Overview

OraDBA Data Safe Extension (odb_datasafe) is an OraDBA extension for comprehensive OCI Data Safe target management. It provides scripts for managing Data Safe targets (list, register, refresh, export, update, delete, move) and a systemd service installer for Data Safe connectors. The extension simplifies Data Safe operations for Oracle DBAs and root administrators.

## Code Quality Standards

### Shell Scripting

- **Always use**: `#!/usr/bin/env bash` (never `#!/bin/sh`)
- **Strict error handling**: Use `set -euo pipefail` for critical scripts
- **ShellCheck compliance**: All scripts must pass shellcheck without warnings
- **Quote variables**: Always quote variables: `"${variable}"` not `$variable`
- **Constants**: Use `readonly` for constants (uppercase names)
- **Variables**: Use lowercase for variables

### Naming Conventions

- **Scripts**: `ds_<action>_<object>.sh` (Data Safe prefix)
- **SQL files**: `ds_<action>_<object>.sql`
- **Tests**: `test_feature.bats`
- **Documentation**: `##_<name>.md` (numbered for ordering)

## Project Structure

```
odb_datasafe/
├── .extension           # Extension metadata (name, version, priority)
├── .checksumignore     # Files excluded from integrity checks
├── VERSION             # Semantic version
├── bin/                # Data Safe management scripts
│   ├── ds_target_list.sh           # List all targets
│   ├── ds_target_register.sh       # Register new target
│   ├── ds_target_refresh.sh        # Refresh target details
│   ├── ds_target_export.sh         # Export target details
│   ├── ds_target_update_connector.sh # Update connector
│   ├── ds_target_delete.sh         # Delete target
│   ├── ds_target_move.sh           # Move to compartment
│   ├── ds_target_details.sh        # Show target info
│   ├── ds_target_connect_details.sh # Show connection
│   ├── ds_target_audit_trail.sh    # Manage audit trails
│   ├── ds_find_untagged_targets.sh # Find untagged targets
│   ├── install_datasafe_service.sh # Service installer (root)
│   └── uninstall_all_datasafe_services.sh # Service uninstaller
├── sql/                # SQL scripts for Data Safe
├── etc/                # Configuration examples
├── lib/                # Shared library functions
├── doc/                # Comprehensive documentation
│   ├── 01_quickref.md             # Quick reference
│   ├── 04_service_installer.md    # Service installer guide
│   └── 05_quickstart_root_admin.md # Root admin guide
├── scripts/            # Build and development tools
└── tests/              # BATS test files

```

## Extension Metadata (.extension)

```ini
name: odb_datasafe
version: 0.5.2
description: OraDBA Data Safe Extension - Comprehensive OCI Data Safe management with service installer and 7 core scripts
author: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
enabled: true
priority: 50
provides:
  bin: true
  sql: true
  rcv: false
  etc: true
  doc: true
```

## Key Features

### Data Safe Target Management

Seven core scripts for complete target lifecycle:
1. **ds_target_list.sh** - List all Data Safe targets
2. **ds_target_register.sh** - Register new database as target
3. **ds_target_refresh.sh** - Refresh target database details
4. **ds_target_export.sh** - Export target configuration
5. **ds_target_update_connector.sh** - Update connector assignment
6. **ds_target_delete.sh** - Delete target
7. **ds_target_move.sh** - Move target to different compartment

### Service Installer (Root Admin)

- **install_datasafe_service.sh** - Install Data Safe connector as systemd service
- **uninstall_all_datasafe_services.sh** - Remove all Data Safe services
- Interactive and non-interactive modes
- Service validation and testing
- Automatic service start on boot
- Proper user/group permissions

## Development Workflow

### Making Changes

1. **Test locally**: Run `make test` before committing
2. **Lint code**: Run `make lint` (shellcheck + markdownlint)
3. **Test OCI integration**: Test with real OCI Data Safe environment
4. **Update docs**: Keep numbered documentation files current
5. **Update CHANGELOG**: Document all changes

### Testing

- **Run all tests**: `make test` or `bats tests/`
- **Test with OCI**: Test scripts against real Data Safe targets (requires OCI CLI configured)
- **Test service installer**: Use `--test` flag for validation without root
- **Test coverage**: Ensure all target operations work correctly

### Building

- **Build package**: `make build` creates tarball in `dist/`
- **Output**: `dist/odb_datasafe-<version>.tar.gz` + `.sha256` checksum
- **Included**: `.extension`, `VERSION`, docs, `bin/`, `sql/`, `etc/`, `lib/`
- **Excluded**: dev tools, `.git*`, build artifacts

## Common Patterns

### Data Safe Script Template

```bash
#!/usr/bin/env bash
#
# Script Name: ds_my_operation.sh
# Description: Data Safe operation script
# Author: Stefan Oehrli
# Version: 1.0.0
#

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

show_usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Data Safe operation script

Options:
    -h, --help              Show this help
    -t, --target-id OCID    Target OCID
    -c, --compartment-id ID Compartment OCID
    -v, --verbose           Verbose output
EOF
}

# Check OCI CLI
check_oci_cli() {
    if ! command -v oci &>/dev/null; then
        echo "Error: OCI CLI not found" >&2
        echo "Install: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm" >&2
        return 1
    fi
}

# Check jq
check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq not found" >&2
        echo "Install: sudo apt-get install jq" >&2
        return 1
    fi
}

main() {
    check_oci_cli
    check_jq
    
    # Main Data Safe logic
    echo "Data Safe operation"
}

# Parse arguments and run
main "$@"
```

### OCI CLI Integration

```bash
# List targets with error handling
list_targets() {
    local compartment_id="$1"
    
    if ! oci data-safe target-database list \
        --compartment-id "${compartment_id}" \
        --all 2>/dev/null; then
        echo "Error: Failed to list targets" >&2
        return 1
    fi
}

# Get target details
get_target() {
    local target_id="$1"
    
    oci data-safe target-database get \
        --target-database-id "${target_id}" \
        | jq -r '.data'
}

# Register new target
register_target() {
    local database_id="$1"
    local compartment_id="$2"
    
    oci data-safe target-database create \
        --database-id "${database_id}" \
        --compartment-id "${compartment_id}" \
        --wait-for-state SUCCEEDED
}
```

### Service Installer Pattern

```bash
# Service installation (requires root)
install_service() {
    local connector_name="$1"
    local user="$2"
    local group="$3"
    
    # Create service file
    cat > "/etc/systemd/system/oracle_datasafe_${connector_name}.service" <<EOF
[Unit]
Description=Oracle Data Safe Connector - ${connector_name}
After=network.target

[Service]
Type=forking
User=${user}
Group=${group}
ExecStart=/u01/app/oracle/${connector_name}/bin/cmctl start
ExecStop=/u01/app/oracle/${connector_name}/bin/cmctl stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable service
    systemctl enable "oracle_datasafe_${connector_name}.service"
    
    # Start service
    systemctl start "oracle_datasafe_${connector_name}.service"
}
```

## Integrity Checking

The `.checksumignore` file excludes dynamic content:

```text
# Extension metadata
.extension
.checksumignore

# Logs
log/
*.log

# OCI credentials and config
.oci/
oci_config

# Temporary files
*.tmp
cache/
```

## Documentation Structure

Numbered documentation for ordered reading:

- **01_quickref.md** - Quick reference for common tasks
- **04_service_installer.md** - Detailed service installer documentation
- **05_quickstart_root_admin.md** - 5-minute root admin setup
- **README.md** - Documentation index

## Integration with OraDBA

### Environment Variables

The extension uses:
- `${ORADBA_BASE}`: OraDBA installation directory
- `${OCI_CLI_CONFIG_FILE}`: OCI CLI configuration
- `${OCI_CLI_PROFILE}`: OCI CLI profile to use

### Auto-Discovery

When installed in `${ORADBA_LOCAL_BASE}`, OraDBA auto-discovers:
- `bin/ds_*.sh` scripts added to PATH
- Extension loaded with priority 50

## Release Process

1. **Update VERSION**: Bump version (e.g., 0.5.2 → 0.5.3)
2. **Update CHANGELOG.md**: Document changes
3. **Update .extension**: Ensure version matches VERSION file and description is current
4. **Test**: Run `make test` and `make lint`
5. **Build**: Run `make build` to verify
6. **Commit**: `git commit -m "chore: Release vX.Y.Z"`
7. **Tag**: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
8. **Push**: `git push origin main --tags`

## When Generating Code

- Follow OCI CLI best practices and patterns
- Use `jq` for JSON processing
- Handle OCI API errors gracefully
- Provide helpful error messages with resolution steps
- Support both interactive and non-interactive modes
- Validate OCIDs before operations
- Add appropriate error handling
- Update documentation (especially numbered docs)
- **Always ask clarifying questions** when requirements are unclear
- **Test with real OCI environment** when possible

## Best Practices

### Error Handling

```bash
# Check prerequisites
if ! command -v oci &>/dev/null; then
    echo "Error: OCI CLI not found" >&2
    echo "Install: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq not found" >&2
    echo "Install: sudo apt-get install jq" >&2
    exit 1
fi

# Validate OCID format
validate_ocid() {
    local ocid="$1"
    if [[ ! "${ocid}" =~ ^ocid1\. ]]; then
        echo "Error: Invalid OCID format: ${ocid}" >&2
        return 1
    fi
}

# Handle OCI CLI errors
if ! result=$(oci data-safe target-database get --target-database-id "${target_id}" 2>&1); then
    echo "Error: Failed to get target details" >&2
    echo "${result}" >&2
    exit 1
fi
```

### JSON Processing

```bash
# Extract single value
target_name=$(echo "${json}" | jq -r '.data."display-name"')

# Extract multiple values
echo "${json}" | jq -r '.data | [
    ."display-name",
    ."lifecycle-state",
    ."time-created"
] | @tsv'

# Filter and format
oci data-safe target-database list \
    --compartment-id "${compartment_id}" \
    --all \
    | jq -r '.data[] | 
        select(."lifecycle-state" == "ACTIVE") |
        [.id, ."display-name", ."database-type"] |
        @tsv'
```

### Service Management

```bash
# Check service status
check_service_status() {
    local service_name="$1"
    
    if systemctl is-active --quiet "${service_name}"; then
        echo "Service ${service_name} is running"
        return 0
    else
        echo "Service ${service_name} is not running" >&2
        return 1
    fi
}

# Validate installation (non-root test)
test_service_installation() {
    local connector_name="$1"
    local connector_path="/u01/app/oracle/${connector_name}"
    
    # Check connector exists
    if [[ ! -d "${connector_path}" ]]; then
        echo "Error: Connector not found at ${connector_path}" >&2
        return 1
    fi
    
    # Check cmctl
    if [[ ! -x "${connector_path}/bin/cmctl" ]]; then
        echo "Error: cmctl not found or not executable" >&2
        return 1
    fi
    
    echo "✓ Connector validation passed"
}
```

## Security Considerations

- Never log or display OCI credentials
- Use OCI CLI profiles for credential management
- Protect service files with appropriate permissions
- Validate all OCIDs before operations
- Use least-privilege principles for service users
- Secure audit trail configurations
- Log security-relevant operations
- Validate file permissions for service installations

## Debugging

```bash
# Enable debug mode
set -x

# Debug OCI CLI
OCI_CLI_DEBUG=1 oci data-safe target-database list --compartment-id "${compartment_id}"

# Check OCI configuration
cat ~/.oci/config
oci setup config --help

# Test connectivity
oci iam region list

# Debug service installation
systemctl status oracle_datasafe_*.service
journalctl -u oracle_datasafe_*.service -n 50
```

## Common Operations

### List All Targets

```bash
./bin/ds_target_list.sh
```

### Register New Target

```bash
./bin/ds_target_register.sh --database-id ocid1.database...
```

### Refresh Target

```bash
./bin/ds_target_refresh.sh --target-id ocid1.datasafetargetdatabase...
```

### Install Service (Root)

```bash
# Interactive
sudo ./bin/install_datasafe_service.sh

# Non-interactive
sudo ./bin/install_datasafe_service.sh \
    --connector ds-conn-name \
    --user oracle \
    --group dba \
    --yes
```

## Resources

- [OCI Data Safe Documentation](https://docs.oracle.com/en-us/iaas/data-safe/)
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/tools/oci-cli/)
- [OraDBA Extension Documentation](doc/)
- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- [ShellCheck](https://www.shellcheck.net/)
