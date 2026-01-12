# OraDBA Data Safe Extension (odb_datasafe)

**Version:** 0.4.0  
**Purpose:** Simplified OCI Data Safe target management and operations

## For Root Administrators

### Install Data Safe Connector as Systemd Service

**Quick Install (3 commands):**

```bash
# 1. List available connectors
./bin/install_datasafe_service.sh --list

# 2. Install service (interactive)
sudo ./bin/install_datasafe_service.sh

# 3. Check service status
sudo systemctl status oracle_datasafe_<connector>.service
```

**Non-Interactive Install:**

```bash
sudo ./bin/install_datasafe_service.sh \
    --connector ds-conn-exacc-p1312 \
    --user oracle \
    --group dba \
    --yes
```

**Test Before Installing (no root needed):**

```bash
./bin/install_datasafe_service.sh --test --connector <name>
```

**Uninstall All Services:**

```bash
sudo ./bin/uninstall_all_datasafe_services.sh
```

➡️ **[Complete Service Installer Guide](doc/05_quickstart_root_admin.md)**

---

## For Oracle Database Administrators

### Quick Commands

```bash
# List all Data Safe targets
./bin/ds_target_list.sh

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
