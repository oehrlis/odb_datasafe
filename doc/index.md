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
tar -xzf odb_datasafe-0.6.0.tar.gz

# Source OraDBA environment
source oraenv.sh
```

The extension is automatically discovered and loaded.

### Configuration

1. **Create environment file** from template in extension base directory:

   ```bash
   cd ${ORADBA_LOCAL_BASE}/odb_d   cd ${ORADBA_LOCAL_BASE}/odb_d   cd ${ORADBA_LOCAL_BASE}/odb_d   cd ${ORADBA_LOCfile must be in the extension base directory.

2. **Co2. **Co2. I a2. **Co2. **Co2. I a2. **Co2. **Co2. I a2. **Co2. **Co2. I a2. **Co2. **Co2. I a2. **Co2. **pecified)
   export DS_ROOT_COMP="ocid1.compartment.oc1..xxx"
   
   # OCI CLI profile (default: DEFAULT)
   export OCI_CLI_PROFILE="DEFAULT"
   ```

3. **Source the environment**:
3. **Source the environment**:
ULT"
LT)
t.oc1..xxx"
Co2. I a2.k Reference](quickref.md)** - Fast reference for commands
- **[Quickstart for - **[Quickstart for - **[Quickstart for - **[Quickstart for erv- **[Quickstavice Installer Guide](install_datasafe_service.md)** - Complete guide
- **[O- **[O P- **[O- **ci-iam-policies.md)** - Required permissions
- **[Release Notes](release_notes/)** - Version hi- ory

## Key Features (v0.6.0)

✅ **Standardized Compartment Handling** - Consistent `-c` and `DS_ROOT_COMP` pattern  
✅ **Reliable Arithmetic** - Fixed shell expressions under `set -e`  
✅ **Flexible Target Selection** - Works with names, OCIDs, or compartment scans  
✅ **Dry-Run Support** - All scripts support `--✅ **Dry-Run Support** - All scripts support `--✅ **Dry-Run Support** - All scripts support `--✅ **Dry-Run Support*  ✅ **Dry-Run Support** - All scripts support `--�-|---------------------------------------|
| `| `| `| `| `| `| `| `| `| `| `| `| L| `| ll | `| `| `| `| `| `| `| `| `| |
| `ds_target_details.sh`            | Get detailed target information       |
| `ds_target_refresh.sh`            | Refr| `ds_target_refresh.sh`            | Refr| `ds_target_refresh.sh`            | Refr| `ds_target_refresh.sh`            | Refr| `ds_target_refresh.sh`            | t database credentials    |
| `ds_target_update_tags.sh`        | Updat| `ds_target_update_tags.sh`        | Updat| `ds_targe.sh| `ds_target_update_taga target from Data Safe        |
| `ds_target_audit_trail.sh`        | Manage audit trail co| `ds_target_    |
| `ds_target_export.sh`             | Export target information             |
| `ds_target_move.sh`               | Move target to diffe| `ds_target_move.sh`               | Move target to diffe| `ds_target_move.sh`               | Move target to diffe| `ds_target_move.sh`               | Move target to diffe| `ds_target_move.sh`               | Move target to diffe| `ds_target_move.sh`         nn| `ds_target_move.sh`               | Move target to diffe| `ds_target_move. Data Safe connector services

## Project Structure

```text
odb_datasafe/
├── bin/           # 16+ executable scripts
├── lib/           # Library framework (ds_lib.sh, common.sh, oci_helpers.sh)
├── doc/           # Documentation (this directory)
├── tests/         # BATS test suite (127├── tests/         # BATS test suite (127├── tests/         # BATS test suite (127├── tests/         # BATS test suite (127├── tes
#############################################################################as############################################################################[Release Notes](release_notes/v0.6.0.md))

See [CHANGELOG.md](../CHANGELOG.md) for complete version history.
