# Script Standardization Status

## Overview

This document tracks the standardization status of all Oracle Data Safe scripts in the `bin/` directory.

**Last Updated**: 2026-01-22

## Standardization Criteria

Scripts should meet these criteria:

- ✅ **SCRIPT_DIR Order**: SCRIPT_DIR defined before SCRIPT_VERSION
- ✅ **Function Headers**: Standardized format for all functions
- ✅ **Compartment Resolution**: Accept name OR OCID, resolve to both
- ✅ **Dry-Run Mode**: Use `oci_exec_ro()` for read-only operations
- ✅ **Error Handling**: No stderr contamination in variable captures
- ✅ **Version Source**: Read from `.extension` file
- ✅ **Syntax Valid**: Passes `bash -n` check

## Fully Standardized Scripts

These scripts follow all standardization patterns from `doc/standardization_pattern.md`:

### Target Update Scripts

| Script                              | SCRIPT_DIR  | Headers  | Resolution  | Dry-Run  | Version  | Status      |
|-------------------------------------|-------------|----------|-------------|----------|----------|-------------|
| **ds_target_update_credentials.sh** | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_update_connector.sh**   | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_update_service.sh**     | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_update_tags.sh**        | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |

### List and Report Scripts

| Script                           | SCRIPT_DIR  | Headers  | Resolution  | Dry-Run  | Version  | Status      |
|----------------------------------|-------------|----------|-------------|----------|----------|-------------|
| **ds_target_list.sh**            | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_list_connector.sh**  | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_refresh.sh**         | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_tg_report.sh**              | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_find_untagged_targets.sh**  | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |

### Management and Registration Scripts

| Script                      | SCRIPT_DIR  | Headers  | Resolution  | Dry-Run  | Version  | Status      |
|-----------------------------|-------------|----------|-------------|----------|----------|-------------|
| **ds_target_delete.sh**     | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |
| **ds_target_register.sh**   | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |

### Template

| Script          | SCRIPT_DIR  | Headers  | Resolution  | Dry-Run  | Version  | Status      |
|-----------------|-------------|----------|-------------|----------|----------|-------------|
| **template.sh** | ✅          | ✅       | ✅          | ✅       | ✅       | ✅ Complete |

## Scripts Using v0.2.0 Framework Pattern

These scripts use a different "minimal bootstrap" pattern with `SCRIPT_BASE` and may not follow the same structure:

| Script                           | Framework | Syntax  | Notes                                                           |
|----------------------------------|-----------|---------|-----------------------------------------------------------------|
| **ds_target_move.sh**            | v0.2.0    | ✅      | Uses `ds_build_target_list()`, `ds_validate_and_fill_targets()` |
| **ds_target_audit_trail.sh**     | v0.2.0    | ✅      | Uses minimal bootstrap pattern                                  |
| **ds_target_connect_details.sh** | v0.2.0    | ✅      | Uses minimal bootstrap pattern                                  |
| **ds_target_details.sh**         | v0.2.0    | ✅      | Uses minimal bootstrap pattern                                  |

**Framework Pattern Differences**:

- Uses `SCRIPT_BASE` instead of `SCRIPT_DIR`
- Loads `SCRIPT_LIB_DIR` from `${SCRIPT_BASE}/lib`
- May use different helper functions from the library
- Hardcoded version numbers (not from `.extension`)

## Scripts Needing Review

| Script                                 | Issues                    | Priority |
|----------------------------------------|---------------------------|----------|
| **install_datasafe_service.sh**        | Needs review              | Low      |
| **uninstall_all_datasafe_services.sh** | Needs review              | Low      |

## Summary Statistics

- **✅ Fully Standardized**: 12 scripts (including template.sh)
- **⚠️ v0.2.0 Framework**: 4 scripts (different pattern, valid)
- **❌ Needs Work**: 2 scripts (install/uninstall - lower priority)

## Recent Completions (2026-01-22)

### ds_target_register.sh ✅

- Updated to read version from `.extension` file
- Fixed SCRIPT_DIR initialization order
- Implemented compartment/connector resolution using helper functions
- Added standardized function headers
- Updated to use `oci_exec()` and `oci_exec_ro()`

### ds_find_untagged_targets.sh ✅

- Updated to read version from `.extension` file (was hardcoded 0.3.0)
- Fixed SCRIPT_DIR initialization order
- Implemented compartment resolution using helper function
- Added standardized function headers
- Updated to use `oci_exec_ro()` for read-only operations

### template.sh ✅

- Complete refresh to reflect latest patterns
- Updated bootstrap with correct order
- Added runtime variables (COMP_NAME, COMP_OCID, TARGET_NAME, TARGET_OCID)
- Implemented resolution pattern examples
- Added comprehensive examples using `oci_exec()` and `oci_exec_ro()`
- Enhanced usage documentation

## Recommendations

### Short Term

1. **install_datasafe_service.sh** - Lower priority
   - Review structure and update if needed
   - Different use case (setup vs. operations)

2. **uninstall_all_datasafe_services.sh** - Lower priority
   - Review structure and update if needed
   - Different use case (cleanup vs. operations)

### Long Term

1. **v0.2.0 Framework Scripts** - Evaluate consolidation
   - Consider migrating to standard pattern OR
   - Document v0.2.0 pattern as alternative for complex scripts (✅ DONE - see `v0.2.0_framework_pattern.md`)
   - Ensure consistency within the pattern

2. **Install/Uninstall Scripts** - Lower priority
   - Review and standardize when time permits
   - Different use case (setup vs. operations)

## Testing Status

- ✅ All standardized scripts pass `bash -n` syntax check
- ⏳ BATS test framework - Not yet implemented
- ⏳ Integration tests - Not yet implemented

## References

- [Standardization Pattern Guide](standardization_pattern.md)
- [v0.2.0 Framework Pattern](v0.2.0_framework_pattern.md)
- [CHANGELOG](../CHANGELOG.md) - All changes documented
- [OraDBA Extension Template](../.github/copilot-instructions.md)

## Change History

| Date       | Change                                          | Scripts Affected             |
|------------|-------------------------------------------------|------------------------------|
| 2026-01-22 | Second round: register, find_untagged, TEMPLATE | 3 scripts                    |
| 2026-01-22 | Added v0.2.0 framework pattern documentation    | Documentation                |
| 2026-01-22 | Initial standardization round                   | 9 scripts fully standardized |
| 2026-01-22 | Added resolution helpers                        | lib/oci_helpers.sh           |
| 2026-01-22 | Created standardization documentation           | standardization_pattern.md   |
