# OraDBA Data Safe Extension (odb_datasafe)

**Version:** 0.7.1  
**Purpose:** Simplified OCI Data Safe target and connector management

## Overview

The `odb_datasafe` extension provides comprehensive tools for managing Oracle OCI Data Safe:

- **Target Management** - Register, refresh, and manage Data Safe database targets
- **Service Installer** - Install Data Safe On-Premises Connectors as systemd services  
- **Connector Management** - List, configure, and manage connectors
- **OCI Integration** - Built on OCI CLI with helper functions
- **Comprehensive Testing** - 227+ BATS tests with full coverage

## Quick Start

### For Administrators

**Install Data Safe Connector:**

```bash
# 1. List available connectors (as oracle user)
./bin/install_datasafe_service.sh --list

# 2. Prepare service config (as oracle user)
./bin/install_datasafe_service.sh --prepare -n my-connector

# 3. Install to system (as root)
sudo ./bin/install_datasafe_service.sh --install -n my-connector

# 4. Verify status
sudo systemctl status oracle_datasafe_my-connector.service
```

**Update Data Safe Connector:**

```bash
# 1. Update connector by name (auto-detects home directory)
./bin/ds_connector_update.sh --connector my-connector -c MyCompartment

# 2. Dry-run to see what would be done
./bin/ds_connector_update.sh --connector my-connector -c MyCompartment --dry-run

# 3. Update with specific home directory
./bin/ds_connector_update.sh --connector my-connector --connector-home /u01/app/oracle/product/datasafe
```

**Uninstall Services:**

```bash
# List installed services
./bin/uninstall_all_datasafe_services.sh --list

# Uninstall all (as root)
sudo ./bin/uninstall_all_datasafe_services.sh --uninstall
```

### For Database Administrators

**Common Tasks:**

```bash
# List all Data Safe targets
./bin/ds_target_list.sh

# List connectors
./bin/ds_target_list_connector.sh

# Show targets grouped by connector (new in v0.6.1)
./bin/ds_target_connector_summary.sh

# Refresh target database
./bin/ds_target_refresh.sh -T my-target

# Export target details
./bin/ds_target_export.sh -T my-target

# Register new target
./bin/ds_target_register.sh -n my-new-target --database-id ocid1.database...
```

**Flexible Compartment Selection:**

```bash
# Uses DS_ROOT_COMP automatically (no -c needed)
export DS_ROOT_COMP="ocid1.compartment.oc1....."
./bin/ds_target_audit_trail.sh -T my-target --dry-run

# Override compartment explicitly
./bin/ds_target_list.sh -c other-compartment

# Scan entire compartment
./bin/ds_target_refresh.sh -c my-compartment
```

## Documentation

📚 **For detailed documentation, see the [doc/](doc/) folder and
[Quick Reference Guide](doc/quickref.md)**

**Quick Access:**

- 🔍 **[Tool Overview](bin/odb_datasafe_help.sh)** — Run
  `./bin/odb_datasafe_help.sh` to list all available scripts and their purposes
- 📖 **[Complete Documentation](doc/index.md)** — Full reference guide
- ⚡ **[Quick Reference](doc/quickref.md)** — Command cheat sheet with examples
- 🔧 **[Installation & Setup](doc/install_datasafe_service.md)** — Detailed setup instructions
- 🔐 **[OCI IAM Policies](doc/oci-iam-policies.md)** — Required IAM permissions
- 📝 **[Release Notes](doc/release_notes/)** — Version history
- 📋 **[CHANGELOG](CHANGELOG.md)** — Detailed change log

## Key Features (v0.7.1)

- ✅ **Connector update automation** — `ds_connector_update.sh` automates
  connector updates with bundle download, password management, and setup.py integration.
- ✅ **Connector visibility** — `ds_target_connector_summary.sh` groups targets
  by connector with lifecycle breakdowns.
  Provides summary and detailed modes with table, JSON, and CSV output.
- ✅ **Authenticated CLI usage** — `require_oci_cli` validates OCI CLI
  authentication with cached checks and helpful errors.
- ✅ **Standardized compartment handling** — Consistent `-c` and `DS_ROOT_COMP` pattern across scripts.
- ✅ **Safe dry-runs and debugging** — Uniform `--dry-run`, `--debug`, and logging behaviors.
- ✅ **Comprehensive testing** — 127+ BATS tests for reliability.

## Requirements

- **OCI CLI** - Oracle Cloud Infrastructure Command Line Interface (`oci`)
- **jq** - JSON processor
- **Bash 4.0+** - Shell interpreter

**Optional (for development):**

- **BATS** - For running tests
- **shellcheck** - For code linting
- **markdownlint** - For documentation linting

## Project Structure

```text
odb_datasafe/
├── bin/              # 16+ executable scripts
├── lib/              # Shared libraries (common.sh, ds_lib.sh, oci_helpers.sh)
├── doc/              # Documentation
├── tests/            # BATS test suite (127+ tests)
├── etc/              # Configuration templates
├── sql/              # SQL utility scripts
└── Makefile         # Build and test automation
```

## Usage Examples

### Basic Target Operations

```bash
# List all targets in root compartment
export DS_ROOT_COMP="ocid1.compartment.oc1....."
ds_target_list.sh

# Get target details
ds_target_details.sh -T my-database

# Update target credentials
ds_target_update_credentials.sh -T my-database --new-password

# Start audit trails
ds_target_audit_trail.sh -T my-database
```

### Advanced Operations

```bash
# Dry-run before making changes
ds_target_move.sh -T my-database -d destination-compartment --dry-run

# Update connector for multiple targets
ds_target_update_connector.sh -c source-compartment --new-connector my-connector

# Export data
ds_target_export.sh -T my-database --format csv
```

## Testing

```bash
# Run all tests
make test

# Run specific test file
bats tests/script_ds_target_list.bats

# Run tests with verbose output
make test-verbose
```

## Support & Contributing

**Author:** Stefan Oehrli (oes)  
**Email:** stefan.oehrli(at)oradba.ch

For issues, feature requests, or contributions, please contact the maintainer.

---

**Getting Started:** See [Installation & Setup](doc/install_datasafe_service.md) for detailed instructions.
