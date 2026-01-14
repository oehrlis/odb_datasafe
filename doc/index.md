# OraDBA Data Safe Extension

Oracle Data Safe management extension for OraDBA - comprehensive tools for managing
OCI Data Safe targets, connectors, and operations.

## Overview

The `odb_datasafe` extension provides a complete framework for working with Oracle Data Safe:

- **Target Management** - Register, update, refresh, and manage Data Safe database targets
- **Service Installer** - Install Data Safe On-Premises Connectors as systemd services
- **OCI Integration** - Helper functions for OCI CLI operations
- **Library Framework** - Reusable shell libraries for Data Safe operations
- **Comprehensive Testing** - BATS test suite with 127+ tests

## Quick Start

### Installation

Extract the extension to your OraDBA local directory:

```bash
cd ${ORADBA_LOCAL_BASE}
tar -xzf odb_datasafe-0.5.1.tar.gz

# Source OraDBA environment
source oraenv.sh
```

The extension is automatically discovered and loaded.

### Configuration

1. **Create environment file** from template:

   ```bash
   cd ${ORADBA_LOCAL_BASE}/odb_datasafe
   cp etc/.env.example .env
   ```

2. **Configure OCI and Data Safe settings** in `.env`:

   ```bash
   # Root compartment OCID
   export DS_ROOT_COMP_OCID="ocid1.compartment.oc1..xxx"
   
   # OCI CLI profile
   export OCI_CLI_PROFILE="DEFAULT"
   
   # Optional: Custom search roots for target databases
   export DS_SEARCH_ROOTS="ocid1.compartment.oc1..xxx,ocid1.compartment.oc1..yyy"
   ```

3. **Source the environment**:

   ```bash
   source .env
   ```

### Basic Usage

```bash
# List all Data Safe targets (table format, default)
ds_target_list.sh

# Show count summary by lifecycle state
ds_target_list.sh -C

# Quiet mode (suppress INFO messages)
ds_target_list.sh -q

# Debug mode (show detailed debug output)
ds_target_list.sh -d

# Get target details
ds_target_details.sh <target-id>

# Refresh a target
ds_target_refresh.sh <target-id>

# Update target credentials
ds_target_update_credentials.sh <target-id>
```

## Documentation

### User Guides

- **[Quick Reference](quickref.md)** - Fast reference for commands, structure, and common tasks
- **[Quickstart for Root Admins](quickstart_root_admin.md)** - 5-minute setup for connector services
- **[Service Installer Guide](install_datasafe_service.md)** - Complete guide for installing Data Safe connector services

### Reference

- **Scripts** - All scripts in `bin/` directory with `--help` option
- **Libraries** - See `lib/README.md` for API documentation
- **Release Notes** - [release_notes/](release_notes/) directory

## Key Features

### Target Management Scripts

Located in `bin/` directory:

| Script                            | Purpose                                   |
|-----------------------------------|-------------------------------------------|
| `ds_target_list.sh`               | List all Data Safe targets                |
| `ds_target_details.sh`            | Get detailed target information           |
| `ds_target_refresh.sh`            | Refresh target in Data Safe               |
| `ds_target_register.sh`           | Register new database target              |
| `ds_target_update_credentials.sh` | Update target database credentials        |
| `ds_target_update_tags.sh`        | Update target tags                        |
| `ds_target_delete.sh`             | Delete a target from Data Safe            |
| `ds_target_audit_trail.sh`        | Manage audit trail configuration          |
| `ds_target_connect_details.sh`    | Get connection details                    |

### Service Management

| Script                                | Purpose                                          |
|---------------------------------------|--------------------------------------------------|
| `install_datasafe_service.sh`         | Install Data Safe connector as systemd service   |
| `uninstall_all_datasafe_services.sh`  | Remove all Data Safe connector services          |

### Library Framework

Located in `lib/` directory:

- **`ds_lib.sh`** - Main loader (sources common.sh and oci_helpers.sh)
- **`common.sh`** - Generic helper functions (logging, error handling, validation)
- **`oci_helpers.sh`** - OCI Data Safe operations (API wrappers, target operations)

See [lib/README.md](../lib/README.md) for API documentation.

## Project Structure

```text
odb_datasafe/
├── .extension              # Extension metadata (v0.5.1)
├── VERSION                 # 0.5.1
├── README.md               # Main documentation
├── CHANGELOG.md            # Release history
├── Makefile                # Development tasks
│
├── bin/                    # Executable scripts (19 scripts)
│   ├── TEMPLATE.sh         # Template for new scripts
│   ├── ds_target_*.sh      # Target management scripts
│   ├── install_datasafe_service.sh
│   └── uninstall_all_datasafe_services.sh
│
├── lib/                    # Library framework
│   ├── ds_lib.sh           # Main loader
│   ├── common.sh           # Generic helpers
│   └── oci_helpers.sh      # OCI Data Safe operations
│
├── etc/                    # Configuration examples
│   ├── .env.example        # Environment template
│   └── datasafe.conf.example
│
├── sql/                    # SQL scripts
├── tests/                  # BATS test suite (15 test files)
└── doc/                    # Documentation
    ├── index.md            # This file
    ├── quickref.md         # Quick reference
    ├── quickstart_root_admin.md
    ├── install_datasafe_service.md
    └── release_notes/      # Version history
```

## Requirements

- **OraDBA** v0.17.0 or later
- **OCI CLI** configured with appropriate profile
- **Bash** 4.0 or later
- **systemd** (for service installer)
- **jq** (for JSON processing)

## Testing

The extension includes a comprehensive test suite:

```bash
# Run tests (excludes integration tests)
make test

# Run all tests including integration
make test-all

# Run specific test file
bats tests/lib_common.bats
```

Test coverage: 127+ tests across 15 test files

## Development

```bash
# Lint all code
make lint

# Format shell scripts
make format

# Run full CI pipeline
make ci

# Build distribution package
make build
```

See [Makefile](../Makefile) for all available targets.

## Support and Contributions

- **Issues** - Report issues on GitHub
- **Documentation** - Complete docs in `doc/` directory
- **Tests** - BATS tests in `tests/` directory
- **Examples** - Configuration examples in `etc/` directory

## License

Apache License 2.0

## Version

Current version: **0.5.1**

See [CHANGELOG.md](../CHANGELOG.md) for version history and [release_notes/](release_notes/) for detailed release documentation.
