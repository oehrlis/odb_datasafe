# OraDBA Data Safe Extension (odb_datasafe)

**Version:** 1.0.0  
**Author:** Stefan Oehrli (oes) stefan.oehrli@oradba.ch  
**Purpose:** Simplified OCI Data Safe target management and operations

## Overview

This OraDBA extension provides a clean, maintainable set of tools for managing Oracle Data Safe targets in OCI. Built from the ground up with simplicity and best practices in mind.

### Design Philosophy (v1.0.0)

- ✅ **Radical Simplicity** - Minimal abstraction, maximum clarity
- ✅ **Modularity** - Clean separation: generic helpers vs OCI-specific
- ✅ **Maintainability** - Easy to understand, modify, and extend
- ✅ **Consistency** - Common patterns across all scripts
- ✅ **Self-documenting** - Clear code with comprehensive inline docs

### Key Features

- **Unified Library Framework** - Shared helpers for logging, error handling, OCI operations
- **Standard CLI Patterns** - Consistent short/long flags across all scripts
- **Configuration Cascade** - Defaults → .env → config file → CLI arguments
- **Comprehensive Logging** - Multiple log levels with optional file output
- **Error Handling** - Robust traps with line numbers and cleanup
- **Dry-run Support** - Test operations safely before execution

## Structure

```text
odb_datasafe/
├── .extension              # Extension metadata
├── VERSION                 # Current version
├── README.md              # This file
├── CHANGELOG.md           # Release history
├── bin/                   # Executable scripts
│   ├── TEMPLATE.sh        # Script template for new tools
│   └── ds_target_refresh.sh
├── lib/                   # Shared libraries
│   ├── ds_lib.sh          # Main loader (sources common + oci_helpers)
│   ├── common.sh          # Generic helpers (logging, args, errors)
│   ├── oci_helpers.sh     # OCI Data Safe operations
│   └── README.md          # Library documentation
├── etc/                   # Configuration examples
│   ├── .env.example       # Environment variables
│   └── datasafe.conf.example  # Main configuration
├── sql/                   # SQL scripts (if needed)
├── tests/                 # Test suite (BATS)
└── scripts/               # Build/dev tools
```

## Quick Start

### Installation

As an OraDBA extension, this is designed to be loaded by the OraDBA framework:

```bash
# Clone or copy to your OraDBA extensions directory
cd $ORADBA_BASE/extensions/
git clone <repo> odb_datasafe

# Verify extension is recognized
oradba extensions list
```

### Configuration

1. **Set environment variables** (optional):
   ```bash
   cp etc/.env.example .env
   # Edit .env with your defaults
   export DS_ROOT_COMP_OCID="ocid1.compartment..."
   export OCI_CLI_PROFILE="DEFAULT"
   ```

2. **Create config file** (optional):
   ```bash
   cp etc/datasafe.conf.example etc/datasafe.conf
   # Edit etc/datasafe.conf for project-specific settings
   ```

3. **Use scripts**:
   ```bash
   # Scripts are added to PATH by OraDBA
   ds_target_refresh.sh --help
   ds_target_refresh.sh -T mydb01 --dry-run
   ```

### Standalone Usage (without OraDBA)

```bash
# Add bin/ to PATH
export PATH="/path/to/odb_datasafe/bin:$PATH"

# Or run directly
./bin/ds_target_refresh.sh --help
```

## Available Scripts

### Target Management

- **`ds_target_refresh.sh`** - Refresh Data Safe target databases
  ```bash
  # Refresh specific targets
  ds_target_refresh.sh -T target1,target2
  
  # Refresh all NEEDS_ATTENTION targets in compartment
  ds_target_refresh.sh -c "MyCompartment" -L NEEDS_ATTENTION
  
  # Dry-run to see what would happen
  ds_target_refresh.sh -T mydb --dry-run --debug
  ```

### Template

- **`TEMPLATE.sh`** - Template for creating new scripts
  - Copy and modify for new functionality
  - Pre-configured with standard patterns

## Configuration Reference

### Environment Variables

```bash
# OCI Configuration
OCI_CLI_PROFILE="DEFAULT"           # OCI CLI profile to use
OCI_CLI_REGION="eu-frankfurt-1"     # OCI region

# Data Safe Defaults
DS_ROOT_COMP_OCID="ocid1.comp..."   # Root compartment for Data Safe
DS_LIFECYCLE="NEEDS_ATTENTION"       # Default lifecycle filter

# Logging
LOG_LEVEL="INFO"                     # DEBUG|INFO|WARN|ERROR
LOG_FILE=""                          # Optional log file path
LOG_COLOR="auto"                     # auto|always|never
```

### Config File Format

See `etc/datasafe.conf.example` for full configuration options.

## Library Reference

### common.sh - Generic Helpers

Core functionality used by all scripts:

- **Logging**: `log()`, `die()`
- **Validation**: `require_cmd()`, `require_env()`
- **Arguments**: `parse_common_flags()`, `get_flag_value()`
- **Utilities**: `normalize_bool()`, `timestamp()`, `cleanup_temp_files()`

### oci_helpers.sh - OCI Data Safe Operations

Data Safe specific operations:

- **Target Operations**: `ds_list_targets()`, `ds_get_target()`, `ds_refresh_target()`
- **Resolution**: `resolve_target_ocid()`, `resolve_compartment()`
- **Tagging**: `ds_update_target_tags()`
- **Utilities**: `oci_exec()`, `oci_wait_for_state()`

See [lib/README.md](lib/README.md) for complete API documentation.

## Development

### Creating New Scripts

1. **Copy the template**:
   ```bash
   cp bin/TEMPLATE.sh bin/ds_new_feature.sh
   ```

2. **Update metadata** in script header (name, purpose, version)

3. **Implement** `parse_args()` with script-specific flags

4. **Add business logic** in main section

5. **Test thoroughly**:
   ```bash
   # Test with dry-run
   ./bin/ds_new_feature.sh --dry-run --debug
   
   # Add BATS tests
   vim tests/ds_new_feature.bats
   ```

### Testing

```bash
# Run all tests
make test

# Or directly with bats
bats tests/

# Test single script
bats tests/ds_target_refresh.bats
```

### Building Release

```bash
# Build extension tarball
./scripts/build.sh

# Output in dist/
ls -l dist/odb_datasafe-1.0.0.tar.gz
```

## Migration from Legacy (datasafe/)

The legacy `datasafe/` project remains unchanged. This extension (`odb_datasafe/`) is a complete rewrite with:

- **90% less code complexity** - Removed over-engineered abstractions
- **Same functionality** - All operations preserved
- **Better maintainability** - Clear, simple patterns
- **Improved debugging** - Better error messages and logging

### Migration Strategy

1. **Test in parallel** - Both systems work independently
2. **Migrate scripts gradually** - One at a time, verify functionality
3. **Deprecate legacy** - Once all critical scripts migrated
4. **Archive old code** - Keep for reference but mark as deprecated

## Support & Contribution

- **Issues**: Report via GitHub issues
- **Documentation**: See inline comments and lib/README.md
- **Questions**: Contact Stefan Oehrli

## License

Apache License Version 2.0 - See LICENSE file

## Related Links

- [Legacy datasafe project](../datasafe/)
- [OraDBA Framework](https://github.com/oradba/oradba)
- [OCI Data Safe Documentation](https://docs.oracle.com/en-us/iaas/data-safe/)

---

**Note**: This is version 1.0.0 - a complete rewrite prioritizing simplicity and maintainability over feature complexity. Feedback welcome!
