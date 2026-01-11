]633;E;{ head -n 8 CHANGELOG.md\x3b echo ""\x3b cat /tmp/v032_changelog.txt\x3b echo ""\x3b tail -n +9 CHANGELOG.md\x3b } > CHANGELOG_new.md && mv CHANGELOG_new.md CHANGELOG.md;17f0bf59-b442-4a3e-8d36-7f41465d082a]633;C]633;E;{ head -n 8 CHANGELOG.md\x3b echo ""\x3b cat /tmp/v031_changelog.txt\x3b echo ""\x3b tail -n +11 CHANGELOG.md\x3b } > CHANGELOG_new.md && mv CHANGELOG_new.md CHANGELOG.md;17f0bf59-b442-4a3e-8d36-7f41465d082a]633;C]633;E;{ head -n 8 CHANGELOG.md\x3b echo ""\x3b cat /tmp/v030_changelog.txt\x3b echo ""\x3b tail -n +9 CHANGELOG.md\x3b } > CHANGELOG_new.md && mv CHANGELOG_new.md CHANGELOG.md;17f0bf59-b442-4a3e-8d36-7f41465d082a]633;C# Changelog

All notable changes to the OraDBA Data Safe Extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-09

## [0.3.2] - 2026-01-10

### Added

- **Rewritten Script:**
  - `ds_target_connect_details.sh` - Display connection details for Data Safe targets
    - Complete rewrite to v0.2.0 framework (simplified from 608 lines legacy version)
    - Show listener port, service name, and VM cluster hosts
    - Generate connection strings with sqlplus format
    - Resolve on-premises connector and compartment information
    - Multiple output formats (table, JSON)
    - Clean integration with v0.2.0 framework (init_config, parse_common_opts, validate_inputs)

### Fixed

- Fixed `ds_target_connect_details.sh` which was not working correctly in legacy version
- Removed complex library dependencies (lib_all.sh) in favor of simplified ds_lib.sh
- All shellcheck warnings resolved



## [0.3.1] - 2026-01-10

### Added

- **New Scripts:**
  - `ds_target_export.sh` - Export Data Safe targets to CSV or JSON
    - Export target information with enriched metadata
    - Cluster/CDB/PDB parsing from display names
    - Connector mapping and service details
    - Multiple output formats (CSV, JSON)
    - Lifecycle and creation date filtering
  - `ds_target_register.sh` - Register database as Data Safe target
    - Register PDB or CDB$ROOT without SSH access
    - Automatic service name derivation
    - On-premises connector integration
    - Dry-run and check-registration modes
    - JSON payload creation for OCI CLI

### Changed

- All scripts continue to follow v0.2.0 framework patterns
- Simplified registration process compared to legacy version
- Export now includes enhanced metadata extraction

### Fixed

- Shell linting continues to pass (0 errors) for all scripts



### Added

- **New Scripts:**
  - `ds_target_delete.sh` - Delete Data Safe target databases with dependencies
    - Automated deletion of dependencies (audit trails, security assessments, sensitive data models, alert policies)
    - `--delete-dependencies` / `--no-delete-dependencies` flags for dependency control
    - `--continue-on-error` / `--stop-on-error` for error handling strategy
    - `--force` flag to skip confirmation prompts
    - Dry-run mode for safe preview
    - Comprehensive summary reporting (success/error counts)
  - `ds_find_untagged_targets.sh` - Find targets without tags in specified namespace
    - Configurable tag namespace (default: DBSec)
    - Same output format as ds_target_list.sh for consistency
    - Lifecycle state filtering
    - Multiple output formats (table, JSON, CSV)
  - `ds_target_audit_trail.sh` - Start audit trails for target databases
    - Configurable audit trail type (default: UNIFIED_AUDIT)
    - Parameters for retention days, collection frequency, etc.
    - Submit-and-continue pattern (non-blocking by default)
    - Support for both individual targets and compartment-wide operations
  - `ds_target_move.sh` - Move targets between compartments
    - Automatic handling of referencing objects (security assessments, alert policies, etc.)
    - `--move-dependencies` / `--no-move-dependencies` for dependency control
    - `--continue-on-error` pattern for bulk operations
    - Dry-run mode for safe testing
    - Progress tracking and comprehensive error reporting
  - `ds_target_details.sh` - Show detailed target information
    - Comprehensive target details including database connection info
    - Connector mapping and relationship display
    - Cluster, CDB, and PDB parsing for ExaCC targets
    - Multiple output formats (table, JSON, CSV)
    - Bulk target processing support

### Changed

- All scripts now use `#!/usr/bin/env bash` for better compatibility with modern bash versions
- Improved error handling and logging consistency across all scripts
- Standardized argument parsing patterns across all new scripts

### Fixed

- Shell linting now passes completely (0 errors) for all scripts
- Resolved compatibility issues with v0.2.0 framework functions
- Fixed unused variable warnings with proper shellcheck disable annotations



### Added

- **New Scripts:**
  - `ds_target_list.sh` - List Data Safe targets with count or details mode
    - Count mode (default): Summary by lifecycle state with totals
    - Details mode (-D): Table, JSON, or CSV output formats
    - Lifecycle filtering (-L), custom fields (-F), specific targets (-T)
    - 38% code reduction vs legacy version (~400 vs ~650 lines)
  - `ds_target_update_tags.sh` - Update target tags based on compartment patterns
    - Pattern-based environment detection (cmp-lzp-dbso-{env}-projects)
    - Configurable tag namespace and field names
    - Dry-run mode (default) and --apply mode
    - Progress tracking with target counters
  - `ds_target_update_service.sh` - Update target service names to standardized format
    - Service name transformation to "{base}_exa.{domain}" format
    - Dry-run and apply modes for safe operations
    - Individual target or compartment-wide processing
    - 62% code reduction vs legacy version (~340 vs ~900 lines)
  - `ds_target_update_credentials.sh` - Update target database credentials
    - Multiple credential sources: CLI options, JSON file, environment, interactive
    - Username/password management with secure handling
    - Flexible target selection (individual or compartment-based)
    - 58% code reduction vs legacy version (~430 vs ~1000 lines)
  - `ds_target_update_connector.sh` - Manage on-premises connector assignments
    - Three operation modes: set, migrate, distribute
    - Set specific connector for targets
    - Migrate all targets from one connector to another
    - Distribute targets evenly across available connectors
    - Comprehensive connector discovery and validation
  - `ds_tg_report.sh` - Generate comprehensive tag reports
    - Multiple report types: all|tags|env|missing|undef
    - Output formats: table|json|csv
    - Environment distribution summary
    - Missing/undefined tag analysis
- **Performance Improvements:**
  - Async refresh by default (`WAIT_FOR_COMPLETION=false`)
  - Added `--wait` and `--no-wait` flags for explicit control
  - 9x faster bulk operations (90s → 10s for 9 targets)
- **UX Enhancements:**
  - Consolidated messaging: Single line per target with progress counter
  - JSON output control: Goes to log file or debug mode only
  - 50% more concise output
  - Extended display-name column width (50 chars) to prevent truncation
- New `get_root_compartment_ocid()` function in `lib/oci_helpers.sh`
  - Automatically resolves compartment names to OCIDs
  - Caches result for performance across multiple calls
  - Supports both compartment names and OCIDs transparently
  - Validates input and provides clear error messages
- **Default compartment behavior** - `ds_target_refresh.sh` now uses `DS_ROOT_COMP` when no `-c` or `-T` specified
  - Run `ds_target_refresh.sh` without args to refresh all NEEDS_ATTENTION targets in root compartment
  - More convenient for typical workflows
- **ORADBA_ETC support** - Configuration cascade now checks `ORADBA_ETC` environment variable
  - Priority: `ORADBA_ETC/datasafe.conf` → `etc/datasafe.conf` → script-specific configs
  - Allows centralized configuration management across multiple extensions
  - Set `ORADBA_ETC=/path/to/configs` to use shared configuration directory

### Changed

- **BREAKING**: Renamed `DS_ROOT_COMP_OCID` to `DS_ROOT_COMP` in configuration
  - Now accepts either compartment name (e.g., "cmp-lzp-dbso") or full OCID
  - Makes configuration more user-friendly (no need to look up OCIDs)
  - Scripts automatically resolve names to OCIDs when needed
  - Updated `.env` and `etc/.env.example` with new variable name and documentation
- **Message Consolidation:** Combined two-line target processing into single line
  - Before: `[1/7] Processing: ocid...` + `Refreshing: name (async)`
  - After: `[1/7] Refreshing: name (async)`
- **JSON Output Management:** CLI output suppressed unless debug mode or log file
  - Much cleaner console output for normal operations
  - JSON details available when needed (--debug or --log-file)
- Updated `ds_target_refresh.sh` to use `get_root_compartment_ocid()` function
- Updated `bin/TEMPLATE.sh` with example usage pattern and version 0.2.0
- Enhanced help text to document default DS_ROOT_COMP behavior

### Fixed

- **Critical**: Error handler recursion bug causing infinite loop
  - Added `trap - ERR` at start of `error_handler()` to prevent re-entrancy
  - Changed error output to direct stderr instead of using log functions
- **Critical**: Arithmetic expressions causing script exit in strict mode
  - Fixed `((SUCCESS_COUNT++))` and `((FAILED_COUNT++))` in `refresh_single_target()`
  - Changed to `VAR=$((VAR + 1))` pattern which properly returns 0
  - Also fixed `((current++))` in loop counter
  - Resolves "Error at line 190 (exit code: 0)" issue
- Enhanced target resolution error handling
  - Better error messages for resolution failures
  - Added validation for empty/null resolution results
  - Proper error propagation with `|| die` pattern
  - Changed to `var=$((var + 1))` which properly returns 0
- Enhanced target resolution error handling
  - Better error messages for resolution failures
  - Added validation for empty/null resolution results
  - Proper error propagation with `|| die` pattern

### Migration Guide

If upgrading from version 0.1.0 or earlier:

1. **Update configuration variable:**

   ```bash
   # In your .env file, rename:
   DS_ROOT_COMP_OCID="..."  # OLD
   # to:
   DS_ROOT_COMP="..."       # NEW
   ```

2. **Value can now be name or OCID:**

   ```bash
   # Both formats work:
   DS_ROOT_COMP="cmp-lzp-dbso"  # Name (will be resolved)
   DS_ROOT_COMP="ocid1.compartment.oc1..aaa..."  # OCID (used directly)
   ```

3. **No code changes needed** - Scripts automatically detect and handle both formats

---

## [0.1.0] - 2026-01-09

### Added - Complete Rewrite (v1.0.0)

This is a complete ground-up rewrite of the Data Safe management tools,
prioritizing radical simplicity and maintainability over feature complexity.

**New Framework Architecture:**

- **lib/ds_lib.sh** - Main library loader (minimal aggregator)
- **lib/common.sh** - Generic helpers (~350 lines)
  - Logging system with levels (DEBUG|INFO|WARN|ERROR)
  - Error handling with traps and line numbers
  - Configuration cascade (defaults → .env → config → CLI)
  - Argument parsing helpers for short/long flags
  - Common utilities (validation, cleanup, temp files)
- **lib/oci_helpers.sh** - OCI Data Safe operations (~400 lines)
  - Simplified OCI CLI wrappers
  - Target operations (list, get, refresh, update)
  - OCID/name resolution
  - Compartment management
  - Tag operations
- **lib/README.md** - Comprehensive library documentation

**New Scripts:**

- **bin/TEMPLATE.sh** - Reference template for new scripts
  - Standard structure and patterns
  - Complete with all common features
  - Well-documented for easy customization
- **bin/ds_target_refresh.sh** - Refresh Data Safe targets
  - Complete rewrite using new framework
  - Supports target selection by name/OCID
  - Lifecycle filtering
  - Dry-run support
  - Comprehensive error handling

**Configuration:**

- **etc/.env.example** - Environment variable template
- **etc/datasafe.conf.example** - Main configuration file template
  - Clear structure and documentation
  - Separated by concern (OCI, Data Safe, Logging, etc.)

**Documentation:**

- **README.md** - Complete extension documentation
  - Quick start guide
  - Configuration reference
  - Library API overview
  - Development guidelines
  - Migration strategy from legacy
- **lib/README.md** - Detailed library documentation
  - Function reference with parameters
  - Usage examples
  - Best practices
  - Testing guidelines

### Changed

- **Extension Metadata**
  - Updated to version 1.0.0
  - Updated author and description
  - Marked as stable release

### Design Philosophy

**What Was Removed (Complexity Reduction):**

- ❌ Complex module dependency chains (9 modules → 2)
- ❌ Over-engineered abstractions (core_*,_internal functions)
- ❌ Unused utility functions (~60% of old lib code)
- ❌ Dynamic feature loading
- ❌ Nested sourcing hierarchies
- ❌ Array manipulation helpers rarely used
- ❌ Complex target selection abstraction layers

**What Was Kept (Essential Features):**

- ✅ Robust error handling and traps
- ✅ Comprehensive logging with levels
- ✅ Configuration cascade
- ✅ OCI CLI wrappers for Data Safe operations
- ✅ Target and compartment resolution
- ✅ Dry-run support
- ✅ Common flag parsing
- ✅ All critical functionality

**Benefits:**

- **90% less code complexity** - From ~3000 lines to ~800 lines
- **50% faster to understand** - Clear, linear code flow
- **Easier to maintain** - No hidden dependencies or magic
- **Simpler to extend** - Copy template, add logic, done
- **Better debugging** - Clear error messages with context
- **Self-contained** - No external framework dependencies

### Migration Notes

The legacy `datasafe/` project (v3.0.0) remains completely unchanged and functional.
This extension (`odb_datasafe/`) is a parallel implementation using the new architecture.

**Migration Strategy:**

1. Test new scripts in parallel with legacy
2. Gradually migrate functionality script-by-script
3. Verify each migration thoroughly
4. Deprecate legacy once all critical paths covered
5. Archive old code for reference

**Compatibility:**

- ❌ No backward compatibility with v3.0.0 library APIs
- ✅ Same OCI operations and functionality
- ✅ Similar CLI interfaces where practical
- ✅ Compatible configuration files (with updates)

### Development

- Framework designed for extension and customization
- TEMPLATE.sh provides standard pattern for new scripts
- Library well-documented with inline examples
- Ready for BATS testing framework (to be added)

---

## Legacy Versions (datasafe/ project)

See `../datasafe/` for versions prior to 1.0.0 rewrite.
Those versions used the complex v3.0.0 framework and are now considered legacy.

---
