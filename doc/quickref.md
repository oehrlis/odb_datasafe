# OraDBA Data Safe Extension - Quick Reference

**Version:** 1.0.0 | **Date:** 2026-01-09

## 📁 Project Structure

```text
odb_datasafe/                          # OraDBA Extension for Data Safe
├── .extension                         # Extension metadata (v1.0.0)
├── VERSION                            # 1.0.0
├── README.md                          # Complete documentation
├── CHANGELOG.md                       # Release history
├── QUICKREF.md                        # This file
├── LICENSE                            # Apache 2.0
│
├── bin/                               # Executable scripts (added to PATH)
│   ├── TEMPLATE.sh                    # Copy this to create new scripts
│   ├── ds_target_refresh.sh           # Refresh Data Safe targets
│   └── extension_tool.sh              # (legacy, can be removed)
│
├── lib/                               # Shared library framework
│   ├── ds_lib.sh                      # Main loader (2 lines, sources both)
│   ├── common.sh                      # Generic helpers (~350 lines)
│   ├── oci_helpers.sh                 # OCI Data Safe ops (~400 lines)
│   └── README.md                      # Library API documentation
│
├── etc/                               # Configuration examples
│   ├── .env.example                   # Environment variables template
│   ├── datasafe.conf.example          # Main config template
│   └── odb_datasafe.conf.example      # (old template, can be removed)
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
# Navigate to extension
cd /path/to/odb_datasafe

# Create environment file
cp etc/.env.example .env
vim .env
  # Set: DS_ROOT_COMP_OCID, OCI_CLI_PROFILE, etc.

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
# Refresh specific target (dry-run first)
bin/ds_target_refresh.sh -T mydb01 --dry-run --debug

# Refresh for real
bin/ds_target_refresh.sh -T mydb01

# Refresh multiple targets
bin/ds_target_refresh.sh -T db1,db2,db3

# Refresh all NEEDS_ATTENTION in compartment
bin/ds_target_refresh.sh -c "MyCompartment" -L NEEDS_ATTENTION
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
cp bin/TEMPLATE.sh bin/ds_new_feature.sh

# 2. Edit metadata (top of file)
vim bin/ds_new_feature.sh
  # Update: SCRIPT_NAME, SCRIPT_PURPOSE, VERSION

# 3. Implement parse_args() for script-specific flags
#    (See TEMPLATE.sh for examples)

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
- **Template**: [bin/TEMPLATE.sh](bin/TEMPLATE.sh)
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
10. **Copy TEMPLATE.sh** - Don't start from scratch

---

**Last Updated:** 2026-01-09  
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
