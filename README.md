# OraDBA Data Safe Extension (odb_datasafe)

**Version:** 0.5.3  
**Purpose:** Simplified OCI Data Safe target management and operations

## For Administrators

### Install Data Safe Connector as Systemd Service

**Two-Phase Workflow:**

```bash
# 1. List available connectors (as oracle user)
./bin/install_datasafe_service.sh --list

# 2. Prepare service config (as oracle user)
./bin/install_datasafe_service.sh --prepare -n my-connector

# 3. Install to system (as root)
sudo ./bin/install_datasafe_service.sh --install -n my-connector

# 4. Check service status
sudo systemctl status oracle_datasafe_my-connector.service
```

**Quick Install (Non-Interactive):**

```bash
# Prepare (as oracle user)
./bin/install_datasafe_service.sh --prepare -n ds-conn-exacc-p1312 --yes

# Install (as root)
sudo ./bin/install_datasafe_service.sh --install -n ds-conn-exacc-p1312 --yes
```

**Check Without Root:**

```bash
./bin/install_datasafe_service.sh --check -n my-connector
```

**Uninstall Services:**

```bash
# List services (as oracle user)
./bin/uninstall_all_datasafe_services.sh --list

# Uninstall all (as root)
sudo ./bin/uninstall_all_datasafe_services.sh --uninstall
```

➡️ **[Complete Service Installer Guide](doc/quickstart_root_admin.md)**

---

## For Oracle Database Administrators

### Quick Commands

```bash
# List all Data Safe targets
./bin/ds_target_list.sh

# List Data Safe on-premises connectors
./bin/ds_target_list_connector.sh

# Refresh target database details
./bin/ds_target_refresh.sh --target-id <ocid>

# Export target details
./bin/ds_target_export.sh --target-id <ocid>

# Register new target
./bin/ds_target_register.sh --database-id <ocid>
```

➡️ **[Quick Reference Guide](doc/01_quickref.md)**

---

## Documentation

- **[Documentation Index](doc/README.md)** - Complete documentation listing
- **[Quick Start](doc/05_quickstart_root_admin.md)** - Root admin 5-minute setup
- **[Service Installer](doc/04_service_installer.md)** - Detailed service installer guide
- **[CHANGELOG](CHANGELOG.md)** - Version history

## Requirements

- **OCI CLI** - Oracle Cloud Infrastructure Command Line Interface
- **jq** - JSON processor
- **Bash 4.0+** - Shell interpreter

**Optional:**

- **BATS** - For running tests
- **shellcheck** - For code linting
- **markdownlint** - For documentation linting

## Quick Setup

1. Clone or copy this extension to your system
2. Configure OCI CLI: `oci setup config`
3. Run any script from `bin/` directory
4. See [doc/README.md](doc/README.md) for detailed documentation

## Project Structure

```text
odb_datasafe/
├── bin/                   # Executable scripts
├── lib/                   # Shared libraries
├── doc/                   # Documentation
├── tests/                 # BATS test suite
├── etc/                   # Configuration examples
└── Makefile              # Build and test targets
```

## Support

**Author:** Stefan Oehrli (oes) <stefan.oehrli@oradba.ch>

**Issues:** For bugs or feature requests, contact the maintainer.

---

**Getting Started:** See [doc/05_quickstart_root_admin.md](doc/05_quickstart_root_admin.md) for immediate setup instructions.
