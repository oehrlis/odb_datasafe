# Script Standardization Pattern

## Overview

This document describes the standardization patterns applied to Oracle Data Safe
scripts for consistent behavior, error handling, and maintainability.

## 1. Script Structure

### Header and Initialization

```bash
#!/usr/bin/env bash
# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Load library - CRITICAL: Define SCRIPT_DIR before using it!
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../lib"
readonly SCRIPT_VERSION="$(grep '^version:' "${SCRIPT_DIR}/../.extension" 2>/dev/null | awk '{print $2}' | tr -d '\n' || echo '0.5.4')"

# Load libraries
source "${LIB_DIR}/ds_lib.sh" || {
    echo "ERROR: Failed to load ds_lib.sh" >&2
    exit 1
}
```

**Common Error**: Defining `SCRIPT_VERSION` before `SCRIPT_DIR`, causing "unbound variable" error.

## 2. Function Headers

All functions must use the standardized header format:

```bash
# ------------------------------------------------------------------------------
# Function: function_name
# Purpose.: Brief description of what the function does
# Args....: $1 - Description of first argument
#           $2 - Description of second argument (optional)
# Returns.: 0 on success, 1 on error
# Output..: Description of what gets printed to stdout
# Notes...: Additional context, usage examples, or warnings (optional)
# ------------------------------------------------------------------------------
function_name() {
    local arg1="$1"
    local arg2="${2:-default}"
    
    # Function implementation
}
```

### Header Fields

- `Function:` - Function name (required)
- `Purpose.:` - Brief description (required)
- `Args....:` - Arguments with descriptions, one per line (if applicable)
- `Returns.:` - Return codes and their meanings (required)
- `Output..:` - What is printed to stdout/stderr (if applicable)
- `Notes...:` - Additional information, examples, warnings (optional)

## 3. Compartment/Target Resolution Pattern

### Using New Helper Functions

```bash
# In validate_inputs():
if [[ -n "$COMPARTMENT" ]]; then
    # Resolve compartment (accepts name OR OCID)
    resolve_compartment_to_vars "$COMPARTMENT" "COMPARTMENT" || {
        die "Cannot resolve compartment '$COMPARTMENT'.\nVerify name or use OCID directly."
    }
    # Now COMPARTMENT_NAME and COMPARTMENT_OCID are both set
    log_info "Using compartment: $COMPARTMENT_NAME"
fi
```

### Manual Resolution (if needed)

```bash
if [[ -n "$COMPARTMENT" ]]; then
    if is_ocid "$COMPARTMENT"; then
        # User provided OCID, resolve to name
        COMPARTMENT_OCID="$COMPARTMENT"
        COMPARTMENT_NAME=$(oci_get_compartment_name "$COMPARTMENT_OCID" 2>/dev/null) || COMPARTMENT_NAME="$COMPARTMENT_OCID"
        log_debug "Resolved compartment OCID to name: $COMPARTMENT_NAME"
    else
        # User provided name, resolve to OCID
        COMPARTMENT_NAME="$COMPARTMENT"
        COMPARTMENT_OCID=$(oci_resolve_compartment_ocid "$COMPARTMENT") || {
            die "Cannot resolve compartment name '$COMPARTMENT' to OCID.\nVerify compartment name or use OCID directly."
        }
        log_debug "Resolved compartment name to OCID: $COMPARTMENT_OCID"
    fi
    log_info "Using compartment: $COMPARTMENT_NAME"
fi
```

**Key Points**:

- Accept both name AND OCID from user
- Store both `_NAME` and `_OCID` internally
- Log with debug messages for troubleshooting
- Provide helpful error messages

## 4. Dry-Run Mode Handling

### Read-Only vs. Modifying Operations

```bash
# Use oci_exec_ro for read-only operations (lookups, lists)
# These ALWAYS execute, even in dry-run mode
result=$(oci_exec_ro iam compartment list --all)

# Use oci_exec for modifying operations (updates, deletes)
# These are skipped in dry-run mode
oci_exec data-safe target-database update --target-database-id "$ocid" ...
```

### Setting DRY_RUN Flag

```bash
# In parse_args():
-n|--dry-run)
    APPLY_CHANGES=false
    shift
    ;;
--apply)
    APPLY_CHANGES=true
    shift
    ;;

# In do_work():
if [[ "$APPLY_CHANGES" == "true" ]]; then
    DRY_RUN=false
    log_info "Apply mode: Changes will be applied"
else
    DRY_RUN=true
    log_info "Dry-run mode: Changes will be shown only (use --apply to apply)"
fi
```

**Critical**: Show dry-run message in `do_work()`, not in `validate_inputs()`, to avoid duplication.

## 5. Variable Capture Without Stderr Contamination

### WRONG - Captures debug messages

```bash
# BAD: This captures stderr (debug messages) into the variable
search_comp_ocid=$(get_root_compartment_ocid 2>&1)
```

### CORRECT - Only captures stdout

```bash
# GOOD: Debug messages go to stderr, only OCID captured
search_comp_ocid=$(get_root_compartment_ocid)
```

**Rule**: Never use `2>&1` when capturing function output unless you specifically need error messages.

## 6. Library Functions

### Resolution Functions (lib/oci_helpers.sh)

#### Low-Level Functions

```bash
# Resolve compartment name to OCID
oci_resolve_compartment_ocid "$name_or_ocid"  # Returns OCID, uses oci_exec_ro

# Resolve target name to OCID  
ds_resolve_target_ocid "$name_or_ocid" "$compartment_ocid"  # Returns OCID, uses oci_exec_ro

# Get compartment name from OCID
oci_get_compartment_name "$ocid"  # Returns name

# Get target name from OCID
ds_resolve_target_name "$ocid"  # Returns display-name
```

#### High-Level Helper Functions

```bash
# Resolve compartment and set both NAME and OCID variables
resolve_compartment_to_vars "$input" "PREFIX"
# Sets: PREFIX_NAME and PREFIX_OCID

# Resolve target and set both NAME and OCID variables
resolve_target_to_vars "$input" "PREFIX" "$compartment_ocid"
# Sets: PREFIX_NAME and PREFIX_OCID
```

### Root Compartment

```bash
# Get DS_ROOT_COMP as OCID (handles name or OCID input)
root_ocid=$(get_root_compartment_ocid) || die "Failed"
```

## 7. Error Handling

### Library Functions Return Codes

All resolution functions in libraries should:

- Return 0 on success, 1 on error
- Output result to stdout
- Log errors to stderr with `log_error`
- NOT call `die` (let calling script handle errors)

### Script Functions Can Use die

```bash
# In scripts, use die for fatal errors
validate_inputs() {
    [[ -n "$REQUIRED_VAR" ]] || die "Missing required option: --required"
}
```

### Error Messages

Provide actionable error messages:

```bash
die "Cannot resolve compartment '$COMPARTMENT'.

Options:
  1. Verify compartment name is correct (case-sensitive)
  2. Use compartment OCID instead: -c ocid1.compartment...
  3. List available compartments: oci iam compartment list --all | jq '.data[] | {name, id}'"
```

## 8. Common Pitfalls

### 1. SCRIPT_DIR Unbound Variable

**Problem**: Using `$SCRIPT_DIR` before it's defined.

**Fix**: Define `SCRIPT_DIR` before using it in `SCRIPT_VERSION` or `LIB_DIR`.

### 2. Debug Messages in Variables

**Problem**: Using `2>&1` captures debug logs into variables.

**Fix**: Remove `2>&1` - let stderr go to terminal.

### 3. Duplicate Dry-Run Messages

**Problem**: Showing dry-run mode in both `validate_inputs()` and `do_work()`.

**Fix**: Show only in `do_work()` where operations happen.

### 4. Dry-Run Blocking Lookups

**Problem**: Read-only operations (compartment/target lookups) blocked in dry-run mode.

**Fix**: Use `oci_exec_ro` instead of `oci_exec` for lookups.

### 5. Die in Library Functions

**Problem**: Library functions calling `die` can't be handled gracefully.

**Fix**: Return error codes, let calling script decide to `die` or handle.

## 9. Testing Checklist

Before committing changes:

```bash
# 1. Syntax check
bash -n script.sh

# 2. Test with --help
./script.sh --help

# 3. Test dry-run mode
./script.sh --dry-run --debug [args...]

# 4. Test with name resolution
./script.sh -c compartment-name --debug

# 5. Test with OCID
./script.sh -c ocid1.compartment... --debug

# 6. Test apply mode
./script.sh --apply --debug [args...]
```

## 10. Migration Checklist

For each script:

- [ ] Fix SCRIPT_DIR order (before SCRIPT_VERSION)
- [ ] Add/update function headers
- [ ] Implement compartment resolution pattern
- [ ] Implement target resolution pattern  
- [ ] Remove `2>&1` from variable captures
- [ ] Use `oci_exec_ro` for read-only operations
- [ ] Show dry-run message only in do_work()
- [ ] Test all modes (help, dry-run, apply)
- [ ] Update CHANGELOG.md
- [ ] Run syntax check

## Examples

See [ds_target_update_credentials.sh](../bin/ds_target_update_credentials.sh) for a complete reference implementation.
