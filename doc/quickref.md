# OraDBA Data Safe Extension - Quick Reference

Current version: see [`../VERSION`](../VERSION) | [Release Notes](release_notes/)

## 📁 Project Structure

```text
odb_datasafe/                          # OraDBA Extension for Data Safe
├── .extension                         # Extension metadata
├── VERSION                            # Current extension version
├── README.md                          # Complete documentation
├── CHANGELOG.md                       # Release history
├── QUICKREF.md                        # This file
├── LICENSE                            # Apache 2.0
│
├── bin/                               # Executable scripts (added to PATH)
│   ├── template.sh                    # Copy this to create new scripts
│   ├── ds_target_list.sh              # List Data Safe targets
│   ├── ds_target_list_connector.sh    # List Data Safe connectors
│   ├── ds_target_connector_summary.sh # Group targets by connector
│   ├── ds_target_refresh.sh           # Refresh Data Safe targets
│   ├── ds_target_update_*.sh          # Update target properties
│   ├── ds_connector_update.sh         # Update Data Safe connector
│   └── install_datasafe_service.sh    # Install connector as service
│
├── lib/                               # Shared library framework
│   ├── ds_lib.sh                      # Main loader (2 lines, sources both)
│   ├── common.sh                      # Generic helpers (~350 lines)
│   ├── oci_helpers.sh                 # OCI Data Safe ops (~400 lines)
│   └── README.md                      # Library API documentation
│
├── etc/                               # Configuration examples
│   ├── datasafe.conf.example          # Main config template
│   └── odb_datasafe.conf.example      # OCI IAM config template
│
├── sql/                               # SQL scripts (added to SQLPATH)
├── tests/                             # Test suite (BATS)
└── scripts/                           # Dev/build tools
    ├── build.sh                       # Build extension tarball
    └── rename-extension.sh            # Rename extension helper
```

## 🚀 Quick Start

### 1. Setup Configuration

```bash
# Navigate to extension base directory
cd /path/to/odb_datasafe  # This is $ODB_DATASAFE_BASE

# Create environment file in base directory (NOT in etc/)
cp etc/.env.example .env
vim .env
  # Set: DS_ROOT_COMP, OCI_CLI_PROFILE, etc.

# IMPORTANT: .env must be in extension base directory:
#   odb_datasafe/.env  <-- HERE (correct)
#   odb_datasafe/etc/.env  <-- WRONG (will not be loaded)

# (Optional) Create config file
cp etc/datasafe.conf.example etc/datasafe.conf
vim etc/datasafe.conf
```

### 2. Test Installation

```bash
# Source environment
source .env

# Test library load
bash -c 'source lib/ds_lib.sh && log "INFO" "Library loaded successfully"'

# Test script
bin/ds_target_refresh.sh --help
```

### 3. Basic Usage

```bash
# Show help overview of all available tools
bin/odb_datasafe_help.sh

# List Data Safe targets (default: table view)
bin/ds_target_list.sh

# List Data Safe on-premises connectors
bin/ds_target_list_connector.sh

# Show summary of targets grouped by connector
bin/ds_target_connector_summary.sh

# Show detailed targets per connector
bin/ds_target_connector_summary.sh -D

# Show count summary by lifecycle state
bin/ds_target_list.sh -C

# Quiet mode (suppress INFO messages)
bin/ds_target_list.sh -q

# Debug mode (detailed logging)
bin/ds_target_list.sh -d

# Filter by lifecycle state
bin/ds_target_list.sh -L NEEDS_ATTENTION
bin/ds_target_list_connector.sh -L ACTIVE

# Output as JSON or CSV
bin/ds_target_list.sh -f json
bin/ds_target_list_connector.sh -f csv -F display-name,id,time-created

# Refresh specific target (dry-run first)
bin/ds_target_refresh.sh -T mydb01 --dry-run --debug

# Refresh for real
bin/ds_target_refresh.sh -T mydb01

# Refresh multiple targets
bin/ds_target_refresh.sh -T db1,db2,db3

# Refresh all NEEDS_ATTENTION in compartment
bin/ds_target_refresh.sh -c "MyCompartment" -L NEEDS_ATTENTION

# Activate INACTIVE targets in a compartment (dry-run by default)
bin/ds_target_activate.sh -c "MyCompartment" -L INACTIVE

# Apply activation changes and wait for completion
bin/ds_target_activate.sh -c "MyCompartment" -L INACTIVE --apply --wait-for-state ACCEPTED

# Activate specific targets by name (requires compartment for resolution)
bin/ds_target_activate.sh -c "MyCompartment" -T db1,db2 --apply

# Show targets with problems (NEEDS_ATTENTION state)
bin/ds_target_list.sh --problems

# Group problems by type with target counts
bin/ds_target_list.sh --group-problems

# Group problems summary only (no target lists)
bin/ds_target_list.sh --group-problems --summary

# Group problems in JSON format for automation  
bin/ds_target_list.sh --group-problems -f json

# Show problems in JSON format for automation
bin/ds_target_list.sh --problems -f json

# Show all fields for a target (JSON only)
bin/ds_target_list.sh -T mydb01 -F all -f json
```

### 4. On-Prem Database Prereqs

`ds_database_prereqs.sh` runs locally on the DB host and creates/updates the
Data Safe profile, user, and grants. You can use the embedded payload in the
script or provide the SQL files on the server. The Oracle environment must be
sourced first.

```bash
# Copy to DB host (embedded payload)
scp bin/ds_database_prereqs.sh oracle@dbhost:/opt/datasafe/
ssh oracle@dbhost chmod 755 /opt/datasafe/ds_database_prereqs.sh

# Copy to DB host (external SQL files)
scp bin/ds_database_prereqs.sh sql/*.sql oracle@dbhost:/opt/datasafe/
ssh oracle@dbhost chmod 755 /opt/datasafe/ds_database_prereqs.sh

# Source environment on DB host
export ORACLE_SID=cdb01
. oraenv <<< "${ORACLE_SID}" >/dev/null

# Run for root or all open PDBs
/opt/datasafe/ds_database_prereqs.sh --root -P "<password>"
/opt/datasafe/ds_database_prereqs.sh --all -P "<password>"

# Base64 password input (auto-decoded)
DS_PW_B64=$(printf '%s' 'mySecret' | base64)
/opt/datasafe/ds_database_prereqs.sh --root -P "${DS_PW_B64}"

# Use embedded payload
/opt/datasafe/ds_database_prereqs.sh --root --embedded -P "<password>"
```

### 5. Getting Help

The `odb_datasafe_help.sh` script provides an overview of all available tools:

```bash
# Show all available tools in table format
bin/odb_datasafe_help.sh

# Export as markdown for documentation
bin/odb_datasafe_help.sh -f markdown

# Export as CSV for processing
bin/odb_datasafe_help.sh -f csv

# Quiet mode (no header/footer)
bin/odb_datasafe_help.sh -q
```

### 6. Target-Connector Summary

The `ds_target_connector_summary.sh` script provides enhanced visibility of the relationship
between targets and on-premises connectors:

```bash
# Show summary of targets grouped by connector (default)
bin/ds_target_connector_summary.sh

# Output shows:
# - Connector name
# - Lifecycle state breakdown per connector
# - Count per lifecycle state
# - Subtotals per connector
# - Grand total of all targets

# Example output:
# Connector                                          Lifecycle State      Count
# -------------------------------------------------- -------------------- ----------
# prod-connector                                     ACTIVE                      5
#                                                    NEEDS_ATTENTION             2
#                                                    Subtotal                    7
#
# test-connector                                     ACTIVE                      3
#                                                    CREATING                    1
#                                                    Subtotal                    4
#
# No Connector (Cloud)                               ACTIVE                     10
#                                                    Subtotal                   10
# -------------------------------------------------- -------------------- ----------
# GRAND TOTAL                                                                   21

# Show detailed list of targets under each connector
bin/ds_target_connector_summary.sh -D

# Filter by lifecycle state (applies to all connectors)
bin/ds_target_connector_summary.sh -L ACTIVE

# Output as JSON (useful for automation)
bin/ds_target_connector_summary.sh -f json

# Output as CSV (useful for reporting)
bin/ds_target_connector_summary.sh -f csv

# Detailed view with custom fields
bin/ds_target_connector_summary.sh -D -F display-name,lifecycle-state,id
```

### 5. Connector Management

```bash
# List all connectors
bin/ds_target_list_connector.sh

# Update a connector (automated update process)
bin/ds_connector_update.sh --connector my-connector -c MyCompartment

# Dry-run to see what would be done
bin/ds_connector_update.sh --connector my-connector -c MyCompartment --dry-run

# Update with specific home directory
bin/ds_connector_update.sh --connector my-connector --connector-home /u01/app/oracle/product/datasafe

# Force new password generation
bin/ds_connector_update.sh --connector my-connector --force-new-password

# Use existing bundle file (skip download)
bin/ds_connector_update.sh --connector my-connector --skip-download --bundle-file /tmp/bundle.zip
```

## 📚 Library Functions (Quick Reference)

### common.sh - Generic Helpers

```bash
# Logging
log "INFO" "message"                    # Log with level
die "error message" [exit_code]         # Log error and exit

# Validation
require_cmd "oci" "jq" "curl"           # Check commands exist
require_env "VAR1" "VAR2"               # Check env vars set

# Configuration
load_env_file "/path/to/.env"           # Load .env file
load_config_file "/path/to/conf"        # Load config file

# Arguments
parse_common_flags "$@"                 # Parse standard flags
get_flag_value "flag_name"              # Get parsed flag value

# Utilities
normalize_bool "yes"                    # Returns: true
timestamp                               # Returns: 2026-01-09T10:30:45Z
cleanup_temp_files                      # Remove temp files on exit
```

### oci_helpers.sh - OCI Data Safe Operations

```bash
# Execute OCI commands
oci_exec "data-safe" "target-database" "list" \
  "--compartment-id" "$comp_id"

# Target operations
ds_list_targets "$compartment_id" "$lifecycle"
ds_get_target "$target_ocid"
ds_refresh_target "$target_ocid"
ds_update_target_tags "$target_ocid" '{"key":"value"}'

# Connector operations
ds_list_connectors "$compartment_id"
ds_resolve_connector_ocid "$name" "$compartment_id"
ds_resolve_connector_name "$connector_ocid"
ds_get_connector_details "$connector_ocid"
ds_generate_connector_bundle "$connector_ocid" "$password"
ds_download_connector_bundle "$connector_ocid" "$output_file"

# Resolution helpers
resolve_target_ocid "target_name"       # Name → OCID
resolve_compartment "comp_name"         # Name → OCID

# Wait/retry
oci_wait_for_state "$resource_ocid" "ACTIVE" [max_wait]
```

## 🛠️ Creating New Scripts

### Step-by-step

```bash
# 1. Copy template
cp bin/template.sh bin/ds_new_feature.sh

# 2. Edit metadata (top of file)
vim bin/ds_new_feature.sh
  # Update: SCRIPT_NAME, SCRIPT_PURPOSE, VERSION

# 3. Implement parse_args() for script-specific flags
#    (See template.sh for examples)

# 4. Add your business logic in main section

# 5. Test
chmod +x bin/ds_new_feature.sh
bin/ds_new_feature.sh --help
bin/ds_new_feature.sh --dry-run --debug
```

### Standard Script Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load library
source "${PROJECT_ROOT}/lib/ds_lib.sh" || exit 1

# Initialize
init_script
load_configuration

# Parse arguments
parse_args "$@"

# Main logic
main() {
    log "INFO" "Starting operation..."
    # Your code here
    log "INFO" "Operation complete"
}

# Run
main
```

## 🎯 Common Flags (Standardized)

All scripts should support these where applicable:

```bash
# Help & Version
-h, --help                    Show usage information
-V, --version                 Show script version

# Logging
-v, --verbose                 Set log level to INFO
-d, --debug                   Set log level to DEBUG
-q, --quiet                   Set log level to ERROR
-l, --log-file <file>         Write logs to file

# Configuration
--config <file>               Load configuration from file
--env <file>                  Load environment from file

# OCI Configuration
--profile <name>              OCI CLI profile (default: $OCI_CLI_PROFILE)
--region <name>               OCI region (default: $OCI_CLI_REGION)

# Execution Control
-n, --dry-run                 Show what would be done (no changes)
-y, --yes                     Skip confirmation prompts
```

## 🧪 Testing

```bash
# Basic smoke test
bin/ds_target_refresh.sh --help
bin/ds_target_refresh.sh -T dummy --dry-run --debug

# Library test
bash -c 'source lib/ds_lib.sh && \
  log "DEBUG" "Debug test" && \
  log "INFO" "Info test" && \
  log "WARN" "Warning test" && \
  echo "All tests passed"'

# Full BATS test (when available)
bats tests/
```

## 📋 Configuration Priority

Configuration is loaded in this order (later overrides earlier):

1. **Code defaults** - Hardcoded in scripts
2. **Environment file** - `.env` in project root or specified location
3. **Config file** - `etc/datasafe.conf` or specified file
4. **CLI arguments** - Command-line flags (highest priority)

### Example Flow

```bash
# 1. Script has default: LOG_LEVEL="INFO"
# 2. .env sets: LOG_LEVEL="WARN"
# 3. datasafe.conf sets: LOG_LEVEL="DEBUG"  
# 4. CLI provides: --debug (sets LOG_LEVEL="DEBUG")
# Result: LOG_LEVEL="DEBUG" (CLI wins)
```

## 🐛 Debugging Tips

```bash
# Maximum verbosity
bin/ds_target_refresh.sh -T target --debug --log-file /tmp/debug.log

# Check library loading
bash -x bin/ds_target_refresh.sh --help 2>&1 | grep -E "source|lib"

# Trace OCI calls
export OCI_CLI_LOG_LEVEL=DEBUG
bin/ds_target_refresh.sh ...

# Dry-run everything
export DRY_RUN=true
bin/ds_target_refresh.sh ...

# Test with minimal config
unset OCI_CLI_PROFILE OCI_CLI_REGION
bin/ds_target_refresh.sh --profile test --region eu-frankfurt-1 ...
```

## 🔗 Useful Links

- **Extension README**: [README.md](README.md)
- **Library Docs**: [lib/README.md](lib/README.md)
- **Template**: [bin/template.sh](bin/template.sh)
- **Config Examples**: [etc/](etc/)
- **Legacy Project**: [../datasafe/](../datasafe/)

## 📊 Version Comparison

| Aspect              | Legacy (v3.0.0)    | New (v1.0.0) |
|---------------------|--------------------|--------------|
| **Library Files**   | 9 modules          | 2 modules    |
| **Total Lines**     | ~3000              | ~800         |
| **Complexity**      | High (nested deps) | Low (flat)   |
| **Learning Curve**  | Steep              | Gentle       |
| **Maintainability** | Difficult          | Easy         |
| **Functionality**   | Full               | Full         |
| **Performance**     | Good               | Better       |

## 💡 Tips & Best Practices

1. **Always test with --dry-run first**
2. **Use --debug for troubleshooting**
3. **Keep scripts under 300 lines** - Extract complex logic to lib/
4. **Document functions** - Inline comments are your friend
5. **Test error paths** - Not just happy paths
6. **Log liberally** - But use appropriate levels
7. **Check return codes** - Don't assume success
8. **Clean up resources** - Use cleanup_temp_files
9. **Validate inputs early** - Fail fast, fail clear
10. **Copy template.sh** - Don't start from scratch

---

**Maintainer:** Stefan Oehrli (oes) <stefan.oehrli@oradba.ch>

## 🆕 New in v0.3.0

### Target Deletion

```bash
# Delete targets with dependencies (audit trails, assessments, policies)
ds_target_delete.sh -T target1,target2 --delete-dependencies --force

# Delete from compartment with confirmation
ds_target_delete.sh -c prod-compartment

# Continue processing even if errors occur
ds_target_delete.sh -T target1,target2,target3 --continue-on-error
```

### Find Untagged Targets

```bash
# Find targets without tags in default DBSec namespace
ds_find_untagged_targets.sh

# Find untagged in specific namespace, CSV output
ds_find_untagged_targets.sh -n Security -o csv

# Find in specific compartment
ds_find_untagged_targets.sh -c prod-compartment
```

### Start Audit Trails

```bash
# Start UNIFIED_AUDIT trails (default)
ds_target_audit_trail.sh -T target1,target2

# Customize audit trail settings
ds_target_audit_trail.sh -c prod-compartment \
  --audit-type UNIFIED_AUDIT \
  --retention-days 180 \
  --collection-frequency WEEKLY
```

### Move Targets Between Compartments

```bash
# Move targets with dependencies
ds_target_move.sh -T target1,target2 -D prod-compartment --move-dependencies

# Move entire compartment of targets
ds_target_move.sh -c test-compartment -D prod-compartment --force

# Dry-run first to see what would happen
ds_target_move.sh -c test-compartment -D prod-compartment --dry-run
```

### Update Target Connectors

```bash
# Set specific connector for target (dry-run by default)
ds_target_update_connector.sh set -T my-target --target-connector conn-prod-01

# Apply connector to specific targets
ds_target_update_connector.sh set -T target1,target2 --target-connector conn-prod-02 --apply

# Include targets needing attention (shortcut for ACTIVE,NEEDS_ATTENTION)
ds_target_update_connector.sh set --target-connector conn-prod-01 --include-needs-attention --apply

# Work with specific lifecycle states
ds_target_update_connector.sh set --target-connector conn-prod-01 -L NEEDS_ATTENTION --apply

# Multiple lifecycle states (comma-separated)
ds_target_update_connector.sh set --target-connector conn-prod-01 -L ACTIVE,NEEDS_ATTENTION --apply

# Migrate all targets from old to new connector
ds_target_update_connector.sh migrate -c my-compartment \
  --source-connector conn-old --target-connector conn-new --apply

# Distribute targets evenly across all available connectors
ds_target_update_connector.sh distribute --apply

# Distribute excluding specific connectors
ds_target_update_connector.sh distribute \
  --exclude-connectors "conn-old,conn-test" --apply
```

### Get Detailed Target Info

```bash
# Show details for specific targets
ds_target_details.sh -T target1,target2

# Show details for all targets in compartment (JSON output)
ds_target_details.sh -c prod-compartment -O json

# Get cluster/CDB/PDB info for specific target
ds_target_details.sh -T my-target-id -O table
```

## 🆕 New in v0.3.1

### Export Targets

```bash
# Export all targets in compartment to CSV
ds_target_export.sh -c prod-compartment

# Export ACTIVE targets to JSON
ds_target_export.sh -c prod-compartment -L ACTIVE -F json -o targets.json

# Export targets created since specific date
ds_target_export.sh -c prod-compartment -D 2025-01-01
```

### Register New Targets

```bash
# Register a PDB
ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \
  -c prod-compartment --connector my-connector --ds-password <password>

# Register CDB$ROOT  
ds_target_register.sh -H db01 --sid cdb01 --root \
  -c prod-compartment --connector my-connector --ds-password <password>

# Check if target already exists
ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \
  -c prod-compartment --connector my-connector --check

# Dry-run to preview registration plan
ds_target_register.sh -H db01 --sid cdb01 --pdb APP1PDB \
  -c prod-compartment --connector my-connector --ds-password <password> --dry-run
```

### New in v0.3.2

**ds_target_connect_details.sh** - Display connection details for Data Safe targets

```bash
# Show connection details for a target (table format)
ds_target_connect_details.sh -T exa118r05c15_cdb09a15_MYPDB

# Get connection details as JSON
ds_target_connect_details.sh -T ocid1.datasafetargetdatabase... -O json

# Specify compartment for name resolution
ds_target_connect_details.sh -T MYPDB -c my-compartment-name

# Get connection details with debug output
ds_target_connect_details.sh -T exa118r05c15_cdb09a15_MYPDB -d
```
