# Data Safe v4.0.0 Library Documentation

## Overview

The v4.0.0 library is a **radical simplification** of the v3.0.0 framework,
focusing on maintainability, clarity, and practical utility. It reduces
complexity by 70% while retaining all essential functionality.

## Philosophy

**Keep it Simple:**

- Flat structure, no deep module nesting
- Explicit over implicit
- Easy to read, easy to modify
- Self-contained scripts with minimal magic

**Core Principles:**

- Each function does one thing well
- No complex abstractions
- Direct OCI CLI interaction with simple wrappers
- Configuration cascade is transparent

## Library Structure

```txt
lib/
├── common.sh         # Generic utilities (~350 lines)
│   ├── Logging system with levels and colors
│   ├── Error handling and cleanup
│   ├── Argument parsing helpers
│   ├── Configuration loading
│   └── Common utilities
│
├── oci_helpers.sh    # OCI-specific functions (~450 lines)
│   ├── OCI CLI wrapper
│   ├── Compartment operations
│   ├── Data Safe target operations
│   ├── Target modifications
│   └── Utilities
│
└── ds_lib.sh         # Convenience loader (~30 lines)
    └── Sources both modules in order
```

## Quick Start

### 1. Create a New Script

```bash
# Copy the template
cp bin/template.sh bin/my_script.sh

# Edit and implement your logic in do_work()
vim bin/my_script.sh
```

### 2. Basic Script Structure

```bash
#!/usr/bin/env bash

# Load library (handles all error setup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ds_lib.sh"

# Configuration
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="4.0.0"

# Your defaults
: "${MY_OPTION:=default_value}"

# Functions
usage() { ... }
parse_args() { ... }
validate_inputs() { ... }
do_work() { ... }

# Main
main() {
    init_config "${SCRIPT_NAME}.conf"
    parse_args "$@"
    validate_inputs
    do_work
}

main "$@"
```

## Common Library (common.sh)

### Logging Functions

```bash
# Log with levels (0=TRACE, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL)
log INFO "Processing started"
log ERROR "Something failed"

# Convenience wrappers
log_trace "Detailed trace info"
log_debug "Debug information"
log_info "General information"
log_warn "Warning message"
log_error "Error message"
log_fatal "Fatal error (exits script)"

# Simple die function
die "Configuration not found" 2  # Exit with code 2
```

**Configuration:**

```bash
LOG_LEVEL=2           # Default: INFO
LOG_FILE="/tmp/my.log"  # Optional file output
LOG_COLORS="auto"     # auto|always|never
```

### Error Handling

```bash
# Automatic setup (enabled by default)
setup_error_handling  # Sets: set -euo pipefail, error traps

# Custom cleanup (override if needed)
cleanup() {
    # Your cleanup code
    rm -f /tmp/tempfile
}

# Error handler features
SHOW_STACKTRACE=true   # Show call stack on error
CLEANUP_ON_EXIT=true   # Call cleanup() on exit
```

### Argument Parsing

```bash
# Parse common options (returns remaining in ARGS)
parse_common_opts "$@"

# Common flags automatically handled:
# -h, --help          : Show usage
# -V, --version       : Show version
# -v, --verbose       : DEBUG level
# -d, --debug         : TRACE level
# -q, --quiet         : WARN level
# -n, --dry-run       : Set DRY_RUN=true
# --log-file FILE     : Set LOG_FILE
# --no-color          : Disable colors

# Then parse your script-specific args
set -- "${ARGS[@]}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--compartment)
            need_val "$1" "${2:-}"  # Validates flag has value
            COMPARTMENT="$2"
            shift 2
            ;;
        # ... more options
    esac
done
```

### Configuration Loading

```bash
# Initialize config cascade
init_config "${SCRIPT_NAME}.conf"

# Loads in order:
#   1. .env (project root)
#   2. etc/datasafe.conf (generic)
#   3. etc/my_script.conf (script-specific)
#   4. Then CLI args override all

# Manual config loading
load_config "/path/to/config.conf"
```

### Validation

```bash
# Check required commands exist
require_cmd oci jq curl

# Check required variables are set
require_var COMPARTMENT OCI_CLI_PROFILE

# Both die with clear error messages if missing
```

### Utilities

```bash
# User confirmation
confirm "Delete all targets?" && do_delete

# Check if string is OCID
if is_ocid "$input"; then
    echo "It's an OCID"
fi
```

## OCI Helpers (oci_helpers.sh)

### OCI CLI Wrapper

```bash
# Execute OCI commands with standard options
oci_exec data-safe target-database list \
    --compartment-id "$comp" \
    --all

# Features:
# - Automatically adds --profile, --region, --config-file
# - Logs commands in debug mode
# - Handles dry-run mode
# - Error logging on failure
```

**Configuration:**

```bash
OCI_CLI_PROFILE="DEFAULT"
OCI_CLI_REGION="eu-frankfurt-1"
OCI_CLI_CONFIG_FILE="${HOME}/.oci/config"
DRY_RUN=false
```

### Compartment Operations

```bash
# Resolve name to OCID (or validate OCID)
comp_ocid=$(oci_resolve_compartment_ocid "MyCompartment")
comp_ocid=$(oci_resolve_compartment_ocid "$ocid")  # validates OCID

# Resolve OCID to name
comp_name=$(oci_resolve_compartment_name "$comp_ocid")
```

### Data Safe Target Operations

```bash
# List targets in compartment
targets=$(ds_list_targets "$comp" "ACTIVE")           # With filter
targets=$(ds_list_targets "$comp")                    # All states

# Get single target details
target=$(ds_get_target "$target_ocid")

# Resolve target name/OCID
target_ocid=$(ds_resolve_target_ocid "my-target" "$comp")
target_name=$(ds_resolve_target_name "$target_ocid")

# Get target's compartment
comp=$(ds_get_target_compartment "$target_ocid")
```

### Target Modifications

```bash
# Refresh target
ds_refresh_target "$target_ocid"

# Update tags
freeform='{"env":"prod","app":"sales"}'
defined='{"DBSec":{"Classification":"confidential"}}'
ds_update_target_tags "$target_ocid" "$freeform" "$defined"

# Update service name
ds_update_target_service "$target_ocid" "mydb_exa.domain.com"

# Delete target
ds_delete_target "$target_ocid"
```

### Utilities

```bash
# Count targets by lifecycle state
summary=$(ds_count_by_lifecycle "$targets_json")
# Output:
#   ACTIVE: 45
#   NEEDS_ATTENTION: 3
#   DELETED: 2
```

## Configuration Cascade

Configuration is loaded in this order (later overrides earlier):

1. **Script Defaults** (in code)

   ```bash
   : "${COMPARTMENT:=}"
   : "${LOG_LEVEL:=2}"
   ```

2. **.env** (project root)

   ```bash
   export OCI_CLI_PROFILE="PROD"
   export DS_ROOT_COMP_OCID="ocid1.compartment..."
   ```

3. **Generic Config** (etc/datasafe.conf)

   ```bash
   COMPARTMENT="ocid1.compartment..."
   LOG_LEVEL=2
   DB_DOMAIN="oradba.ch"
   ```

4. **Script-Specific Config** (etc/my_script.conf)

   ```bash
   LIFECYCLE_STATE="ACTIVE"
   CUSTOM_SETTING="value"
   ```

5. **CLI Arguments** (highest priority)

   ```bash
   ./my_script.sh -c OtherCompartment --debug
   ```

## Script Patterns

### Pattern 1: List/Query Operations

```bash
do_work() {
    comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT")
    targets=$(ds_list_targets "$comp_ocid" "$LIFECYCLE_STATE")
    
    echo "$targets" | jq -r '.data[] | "\(.["display-name"]): \(.["lifecycle-state"])"'
}
```

### Pattern 2: Single Target Operation

```bash
do_work() {
    target_ocid=$(ds_resolve_target_ocid "$TARGET" "$COMPARTMENT")
    target_name=$(ds_resolve_target_name "$target_ocid")
    
    log_info "Processing: $target_name"
    ds_refresh_target "$target_ocid"
}
```

### Pattern 3: Batch Operations

```bash
do_work() {
    IFS=',' read -ra target_list <<< "$TARGETS"
    
    for target in "${target_list[@]}"; do
        target_ocid=$(ds_resolve_target_ocid "$target" "$COMPARTMENT")
        
        if ds_refresh_target "$target_ocid"; then
            ((SUCCESS++))
        else
            ((FAILED++))
        fi
    done
    
    log_info "Success: $SUCCESS, Failed: $FAILED"
}
```

### Pattern 4: Discovery + Action

```bash
do_work() {
    # Discover targets
    comp_ocid=$(oci_resolve_compartment_ocid "$COMPARTMENT")
    targets=$(ds_list_targets "$comp_ocid" "NEEDS_ATTENTION")
    
    # Process each
    echo "$targets" | jq -r '.data[].id' | while read -r target_ocid; do
        target_name=$(ds_resolve_target_name "$target_ocid")
        log_info "Fixing: $target_name"
        
        # Do something
        ds_refresh_target "$target_ocid"
    done
}
```

## Testing Your Script

```bash
# Test with dry-run
./bin/my_script.sh --dry-run -v

# Test with debug logging
./bin/my_script.sh --debug

# Test with specific target
./bin/my_script.sh -T my-target --dry-run

# Test with log file
./bin/my_script.sh --log-file /tmp/test.log
```

## Common Patterns & Idioms

### Safely Process Array of Targets

```bash
mapfile -t targets < <(echo "$json" | jq -r '.data[].id')

for target in "${targets[@]}"; do
    # Process each
done
```

### Conditional Action Based on State

```bash
state=$(echo "$target_json" | jq -r '.data["lifecycle-state"]')

if [[ "$state" == "NEEDS_ATTENTION" ]]; then
    ds_refresh_target "$target_ocid"
fi
```

### Handle Errors Gracefully

```bash
if target_ocid=$(ds_resolve_target_ocid "$name" "$comp" 2>/dev/null); then
    log_info "Found: $target_ocid"
else
    log_warn "Target not found: $name"
    continue
fi
```

### Progress Tracking

```bash
total=${#targets[@]}
current=0

for target in "${targets[@]}"; do
    ((current++))
    log_info "[$current/$total] Processing: $target"
    # Do work
done
```

## Comparison: v3 vs v4

| Aspect             | v3.0.0        | v4.0.0       |
|--------------------|---------------|--------------|
| **Library Files**  | 10+ modules   | 3 files      |
| **Total Lines**    | ~5000+        | ~850         |
| **Dependencies**   | Complex chain | Simple       |
| **Learning Curve** | High          | Low          |
| **Debuggability**  | Difficult     | Easy         |
| **Extensibility**  | Framework     | Direct       |
| **Script Length**  | 200-500 lines | 80-150 lines |

## Migration Guide

### Step 1: New Script from Scratch

1. Copy template.sh
2. Implement `do_work()`
3. Test

### Step 2: Migrate Existing Script

1. Create new script in bin/
2. Copy business logic from old script
3. Replace v3 functions with v4 equivalents:

| v3 Function                    | v4 Equivalent            |
|--------------------------------|--------------------------|
| `core_log_message INFO`        | `log_info`               |
| `core_exit_script`             | `die`                    |
| `oci_run`                      | `oci_exec`               |
| `core_parse_common_flags`      | `parse_common_opts`      |
| `core_target_preflight_select` | Manual list + filter     |
| `oci_ds_resolve_target_ocid`   | `ds_resolve_target_ocid` |

1. Test thoroughly
2. Keep old script until confident

### Step 3: Gradual Rollout

- Both v3 and v4 coexist
- Migrate scripts one at a time
- No breaking changes to existing workflows
- Eventually deprecate v3

## Best Practices

1. **Keep functions small**: One purpose per function
2. **Log appropriately**: INFO for progress, DEBUG for details, ERROR for problems
3. **Validate early**: Check inputs before doing work
4. **Handle errors gracefully**: Don't let one failure stop everything
5. **Use dry-run**: Test logic without making changes
6. **Document as you go**: Update usage() with examples
7. **Test incrementally**: Don't write 200 lines then test

## Troubleshooting

### Enable Debug Logging

```bash
./script.sh --debug
```

### Check OCI Commands

```bash
LOG_LEVEL=0 ./script.sh  # TRACE level shows all OCI commands
```

### Dry-Run Mode

```bash
./script.sh --dry-run  # Shows what would happen
```

### Check Configuration

```bash
# Add to script temporarily
log_debug "COMPARTMENT=$COMPARTMENT"
log_debug "OCI_CLI_PROFILE=$OCI_CLI_PROFILE"
```

## Need Help?

1. Check [template.sh](../bin/template.sh) for structure
2. Check [ds_target_refresh.sh](../bin/ds_target_refresh.sh) for real example
3. Read function comments in library files
4. Use `--debug` mode to see what's happening

## Future Enhancements

Possible additions without adding complexity:

- Parallel execution helper (GNU parallel)
- Progress bars for long operations
- JSON/CSV output formatters
- Retry logic for transient errors
- BATS test framework integration
