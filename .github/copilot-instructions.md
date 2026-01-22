# GitHub Copilot Instructions for OraDBA Extension Template

## Project Overview

OraDBA Extension Template is a ready-to-use template for creating OraDBA extensions. Extensions add custom scripts, SQL queries, RMAN backups, and configurations to OraDBA installations. This template provides a complete project structure with CI/CD, testing, and release automation.

## Code Quality Standards

### Shell Scripting

- **Always use**: `#!/usr/bin/env bash` (never `#!/bin/sh`)
- **Strict error handling**: Use `set -euo pipefail` for critical scripts
- **ShellCheck compliance**: All scripts must pass shellcheck without warnings
- **Quote variables**: Always quote variables: `"${variable}"` not `$variable`
- **Constants**: Use `readonly` for constants (uppercase names)
- **Variables**: Use lowercase for variables

### Naming Conventions

- **Scripts**: `lowercase_with_underscores.sh`
- **SQL files**: `lowercase_with_underscores.sql`
- **RMAN files**: `lowercase_with_underscores.rcv`
- **Tests**: `test_feature.bats`
- **Documentation**: `lowercase-with-hyphens.md`

## Project Structure

```
oradba_extension/
├── .extension           # Extension metadata (name, version, priority)
├── .checksumignore     # Files excluded from integrity checks
├── VERSION             # Semantic version
├── bin/                # Executable scripts (added to PATH)
├── sql/                # SQL scripts (added to SQLPATH)
├── rcv/                # RMAN scripts
├── etc/                # Configuration examples
├── lib/                # Shared library functions
├── scripts/            # Build and development tools
├── tests/              # BATS test files
└── doc/                # Documentation

```

## Extension Metadata (.extension)

The `.extension` file defines extension properties:

```ini
name: my_extension
version: 1.0.0
description: Brief description of extension
author: Author Name
enabled: true
priority: 50
provides:
  bin: true
  sql: true
  rcv: true
  etc: true
  doc: true
```

**Key fields:**
- `name`: Extension identifier (lowercase, no spaces)
- `version`: Semantic version (MAJOR.MINOR.PATCH)
- `priority`: Load order (lower = earlier, 0-100)
- `provides`: Declares which directories the extension uses

## Development Workflow

### Creating a New Extension

1. **Clone template**: `git clone https://github.com/oehrlis/oradba_extension.git my_extension`
2. **Rename extension**: `./scripts/rename-extension.sh --name myext --description "My extension"`
3. **Update VERSION**: Set initial version
4. **Implement**: Add scripts to `bin/`, `sql/`, `rcv/`, `lib/`
5. **Test**: Add tests to `tests/` and run `make test`
6. **Document**: Update `README.md` and `doc/`

### Making Changes

1. **Test locally**: Run `make test` before committing
2. **Lint code**: Run `make lint` (shellcheck + markdownlint)
3. **Update tests**: Add/update tests for new functionality
4. **Update docs**: Keep documentation in sync
5. **Update CHANGELOG**: Document changes in CHANGELOG.md

### Testing

- **Run all tests**: `make test` or `bats tests/`
- **Specific test**: `bats tests/test_file.bats`
- **Verbose output**: `bats -t tests/`
- **Test coverage**: Aim for high coverage of custom scripts

### Building

- **Build package**: `make build` creates tarball in `dist/`
- **Output**: `dist/<name>-<version>.tar.gz` + `.sha256` checksum
- **Included files**: `.extension`, `VERSION`, `README.md`, `CHANGELOG.md`, `LICENSE`, `bin/`, `sql/`, `rcv/`, `etc/`, `lib/`, `doc/`
- **Excluded files**: `scripts/`, `tests/`, `.github/`, `dist/`, `.git*`

## Common Patterns

### Script Template

```bash
#!/usr/bin/env bash
#
# Script Name: my_tool.sh
# Description: Brief description
# Author: Your Name
# Version: 1.0.0
#

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

# ------------------------------------------------------------------------------
# Function: show_usage
# Purpose.: Display usage information
# Returns.: 0
# Output..: Usage information to stdout
# ------------------------------------------------------------------------------
show_usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
    -h, --help          Show this help
    -v, --verbose       Verbose output
EOF
}

# ------------------------------------------------------------------------------
# Function: main
# Purpose.: Main entry point for the script
# Returns.: 0 on success, 1 on error
# ------------------------------------------------------------------------------
main() {
    # Check OraDBA environment
    if [[ -z "${ORADBA_BASE:-}" ]]; then
        echo "Error: OraDBA not loaded" >&2
        exit 1
    fi
    
    # Main logic here
    echo "Script running"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: ${1}" >&2
            show_usage
            exit 1
            ;;
    esac
done

main
```

### Function Header Template

All functions must include standardized headers:

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

**Header Field Descriptions:**
- `Function:` - Function name (required)
- `Purpose.:` - Brief description (required)
- `Args....:` - Arguments with descriptions, one per line (if applicable)
- `Returns.:` - Return codes and their meanings (required)
- `Output..:` - What is printed to stdout/stderr (if applicable)
- `Notes...:` - Additional information, examples, warnings (optional)

### SQL Script Template

```sql
-- ============================================================================
-- Script: my_query.sql
-- Description: Brief description
-- ============================================================================

SET LINESIZE 200
SET PAGESIZE 1000

SELECT name, value
FROM v$parameter
WHERE name LIKE '%memory%'
ORDER BY name;
```

### RMAN Script Template

```sql
-- ============================================================================
-- RMAN: my_backup.rcv
-- Description: Brief description
-- ============================================================================

CONFIGURE RETENTION POLICY TO REDUNDANCY 2;

RUN {
    ALLOCATE CHANNEL disk1 DEVICE TYPE DISK;
    BACKUP DATABASE PLUS ARCHIVELOG;
    DELETE NOPROMPT OBSOLETE;
    RELEASE CHANNEL disk1;
}
```

### Test Template

```bash
#!/usr/bin/env bats

setup() {
    export TEST_DIR="${BATS_TEST_TMPDIR}/test_$$"
    mkdir -p "${TEST_DIR}"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "Extension metadata exists" {
    [ -f .extension ]
}

@test "My script is executable" {
    [ -x bin/my_tool.sh ]
}
```

## Integrity Checking

The `.checksumignore` file excludes files from integrity verification:

```text
# Extension metadata (always excluded)
.extension
.checksumignore

# Logs and temporary files
log/
*.log
*.tmp

# User-specific configurations
keystore/
*.key
```

**Common exclusions:**
- Log directories and files
- Credentials and secrets
- Cache and temporary files
- User-specific configs

## Release Process

1. **Update VERSION**: Bump version following semantic versioning
2. **Update CHANGELOG.md**: Document all changes
3. **Update .extension**: Ensure version matches VERSION file
4. **Test**: Run `make test` and `make lint`
5. **Build**: Run `make build` to verify build succeeds
6. **Commit**: `git add . && git commit -m "chore: Release vX.Y.Z"`
7. **Tag**: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
8. **Push**: `git push origin main --tags`

**Note**: GitHub Actions automatically builds and publishes releases when tags are pushed.

## When Generating Code

- Follow existing template patterns for scripts
- Use strict error handling (`set -euo pipefail`)
- Always check for OraDBA environment (`${ORADBA_BASE}`)
- Quote all variables
- Add appropriate tests for new functionality
- Update documentation
- **Always ask clarifying questions** when requirements are unclear
- **Avoid hardcoded values** - Use variables and configuration

## Best Practices

### Error Handling

```bash
# Check prerequisites
if [[ ! -d "${ORADBA_BASE}" ]]; then
    echo "Error: OraDBA not found" >&2
    exit 1
fi

# Check Oracle environment
if [[ -z "${ORACLE_HOME:-}" ]]; then
    echo "Error: ORACLE_HOME not set" >&2
    exit 1
fi

# Validate input
if [[ -z "${database_sid}" ]]; then
    echo "Error: Database SID required" >&2
    exit 1
fi
```

### File Operations

```bash
# Safe file creation
if [[ -f "${output_file}" ]]; then
    echo "Warning: File exists, backing up" >&2
    cp "${output_file}" "${output_file}.bak"
fi

# Temporary files
temp_file=$(mktemp)
trap 'rm -f "${temp_file}"' EXIT
```

### Logging

```bash
# Use consistent logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log "Starting process"
log "Process completed"
```

## Integration with OraDBA

### Environment Variables

Extensions can access OraDBA variables:
- `${ORADBA_BASE}`: OraDBA installation directory
- `${ORADBA_PREFIX}`: OraDBA prefix path
- `${ORACLE_HOME}`: Current Oracle Home
- `${ORACLE_SID}`: Current database SID

### Loading Extensions

OraDBA auto-discovers extensions in:
- `${ORADBA_LOCAL_BASE}/*/bin/*.sh` (executable scripts)
- `${ORADBA_LOCAL_BASE}/*/sql/*.sql` (SQL scripts)
- `${ORADBA_LOCAL_BASE}/*/rcv/*.rcv` (RMAN scripts)

### Configuration

Users copy settings from `etc/<name>.conf.example` to:
- `${ORADBA_PREFIX}/etc/oradba_customer.conf` (site-wide)
- Or load directly in extension scripts

## Security Considerations

- Never hardcode passwords or credentials
- Use environment variables for sensitive data
- Validate all user inputs
- Check file permissions before operations
- Use secure defaults
- Log security-relevant events

## Documentation

- **README.md**: Quick start and overview
- **doc/index.md**: Main documentation
- **doc/installation.md**: Installation guide
- **doc/configuration.md**: Configuration reference
- **doc/reference.md**: API and script reference
- **CHANGELOG.md**: Version history

Keep documentation concise, clear, and current with code changes.

## Debugging

```bash
# Enable debug mode
set -x

# Debug specific section
(set -x; my_function)

# Add debug output
if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "DEBUG: variable=${variable}" >&2
fi
```

## Resources

- [OraDBA Extension Documentation](doc/development.md)
- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- [BATS Testing](https://bats-core.readthedocs.io/)
- [ShellCheck](https://www.shellcheck.net/)
