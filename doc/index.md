# OraDBA Data Safe Extension

Oracle Data Safe management extension for OraDBA - comprehensive tools for managing
OCI Data Safe targets, connectors, and operations.

Current version: see [`../VERSION`](../VERSION) | [Release Notes](release_notes/)
Latest release: [v0.16.2](release_notes/v0.16.2.md)

## Overview

The `odb_datasafe` extension provides a complete framework for working with Oracle Data Safe:

- **Target Management** - Register, update, refresh, and manage Data Safe database targets
- **Service Installer** - Install Data Safe On-Premises Connectors as systemd services
- **OCI Integration** - Helper functions for OCI CLI operations
- **Library Framework** - Reusable shell libraries for Data Safe operations
- **Comprehensive Testing** - BATS test suite with 127+ tests

## Documentation

- **[Project README](../README.md)** - Top-level overview and common workflows
- **[Quick Reference](quickref.md)** - Fast reference for all commands
- **[Standalone Usage](standalone_usage.md)** - Run `odb_datasafe` directly from its folder
- **[Installation Guide](install_datasafe_service.md)** - Setup instructions
- **[Troubleshooting Guide](troubleshooting.md)** - Health overview and actions
- **[Database Prereqs](database_prereqs.md)** - On-prem DB preparation
- **[IAM Policies Guide](oci-iam-policies.md)** - Required OCI permissions
- **[Release Notes](release_notes/)** - Version history and changes
- **[v0.16.2 Release Note](release_notes/v0.16.2.md)** - CLI consolidation,
  registration defaults, and shell-compatibility hardening
- **[CHANGELOG](../CHANGELOG.md)** - Complete version history

## Quick Start

### Installation

Extract the extension to your OraDBA local directory:

```bash
cd ${ORADBA_LOCAL_BASE}
tar -xzf odb_datasafe-<version>.tar.gz

# Source OraDBA environment
source oraenv.sh
```

The extension is automatically discovered and loaded.

### Configuration

1. **Create environment file** from template:

   ```bash
   cd ${ORADBA_LOCAL_BASE}/odb_datasafe
   cp etc/.env.example .env
   vim .env
   ```

2. **Set required environment variables**:

   ```bash
   # Data Safe root compartment (OCID or compartment name)
   export DS_ROOT_COMP="ocid1.compartment.oc1..xxx"
   
   # OCI CLI profile (default: DEFAULT)
   export OCI_CLI_PROFILE="DEFAULT"
   ```

3. **Source the environment**:

   ```bash
   source .env
   ```

### First Steps

```bash
# List Data Safe targets
bin/ds_target_list.sh

# Get help for any command
bin/ds_target_refresh.sh --help

# Test with dry-run
bin/ds_target_refresh.sh -T mydb01 --dry-run
```

## Key Features

- ✅ **Standalone usage guide** — `doc/standalone_usage.md` provides tarball install and minimal run steps.
- ✅ **Help wrapper and config visibility** — `datasafe_help.sh` plus config/OCI config summaries in help output.
- ✅ **Connector check modes (`v0.11.2`)** — `ds_connector_update.sh`
   supports `--check-only` for single connectors and `--check-all` for batch checks of
   `product=datasafe` entries in OraDBA config.
- ✅ **Consistent script headers** — function/script header format standardized across `bin/` and `lib/`.
- ✅ **Reporting fix in target-group report** — `ds_tg_report.sh` handles `display-name` field access correctly.

## Available Scripts

| Script                               | Purpose                                |
|--------------------------------------|----------------------------------------|
| `ds_target_list.sh`                  | List Data Safe targets with filtering  |
| `ds_target_list_connector.sh`        | List Data Safe on-premises connectors  |
| `ds_target_details.sh`               | Show detailed target information       |
| `ds_target_refresh.sh`               | Refresh target database credentials    |
| `ds_target_register.sh`              | Register new Data Safe target          |
| `ds_target_update_connector.sh`      | Update target connector                |
| `ds_target_update_credentials.sh`    | Update target credentials              |
| `ds_target_update_service.sh`        | Update connector service configuration |
| `ds_target_update_tags.sh`           | Update target tags                     |
| `ds_target_delete.sh`                | Remove Data Safe target                |
| `ds_target_audit_trail.sh`           | Manage audit trail configuration       |
| `ds_target_export.sh`                | Export target information              |
| `ds_target_move.sh`                  | Move target to different compartment   |
| `ds_target_connect_details.sh`       | Show connection details                |
| `ds_find_untagged_targets.sh`        | Find targets without tags              |
| `ds_tg_report.sh`                    | Generate target group report           |
| `install_datasafe_service.sh`        | Install connector as systemd service   |
| `uninstall_all_datasafe_services.sh` | Remove all connector services          |

## Project Structure

```text
odb_datasafe/
├── bin/           # 16+ executable scripts
├── lib/           # Library framework (ds_lib.sh, common.sh, oci_helpers.sh)
├── doc/           # Documentation (this directory)
├── tests/         # BATS test suite (127+ tests)
├── etc/           # Configuration examples
├── sql/           # SQL queries
├── VERSION        # Current version
├── CHANGELOG.md   # Version history
└── README.md      # Project overview
```

## Common Flags

All scripts support:

```bash
-h, --help         Show usage information
-d, --debug        Enable debug logging
-q, --quiet        Suppress info messages
-n, --dry-run      Show what would be done (no changes)
-v, --verbose      Verbose output
```

Many scripts also support:

```bash
-A, --all          Select all targets from DS_ROOT_COMP
-c, --compartment  Compartment name or OCID
-T, --target       Target database name or OCID
-L, --lifecycle    Filter by lifecycle state
-f, --format       Output format (table, json, csv)
-r, --filter       Filter target display names with regex
```

### All Targets from DS_ROOT_COMP

The following scripts support `-A/--all` to explicitly scope operations to all
targets under `DS_ROOT_COMP`:

- `bin/ds_target_list.sh`
- `bin/ds_target_refresh.sh`
- `bin/ds_target_activate.sh`
- `bin/ds_target_update_credentials.sh`
- `bin/ds_target_update_connector.sh`
- `bin/ds_target_update_service.sh`
- `bin/ds_target_update_tags.sh`

Behavior:

- `--all` requires `DS_ROOT_COMP` to be configured.
- `--all` cannot be combined with `-c/--compartment` or `-T/--target(s)`.

### Target Name Regex Filter

The following scripts support `-r/--filter` to process only targets where the
target display name matches a regex:

- `bin/ds_target_list.sh`
- `bin/ds_target_refresh.sh`
- `bin/ds_target_activate.sh`
- `bin/ds_target_update_credentials.sh`
- `bin/ds_target_update_connector.sh`
- `bin/ds_target_update_service.sh`
- `bin/ds_target_update_tags.sh`

Behavior:

- Regex substring match is applied to the target display name.
- When combined with `-T/--target(s)`, only matching targets from that set are used.
- Mutating scripts exit with code `1` when no targets match.
- `bin/ds_target_list.sh` returns an informational empty result when no targets match.

## Examples

### List Operations

```bash
# List all targets
bin/ds_target_list.sh

# List targets by state
bin/ds_target_list.sh -L NEEDS_ATTENTION

# Show count summary
bin/ds_target_list.sh -C

# Mode group selector: overview
bin/ds_target_list.sh -G overview

# Mode group selector: troubleshooting (defaults to health overview)
bin/ds_target_list.sh -G troubleshooting

# Output as JSON
bin/ds_target_list.sh -f json

# List targets with names containing db02
bin/ds_target_list.sh -r "db02"

# List NEEDS_ATTENTION targets where name contains db02
bin/ds_target_list.sh -L NEEDS_ATTENTION -r "db02"

# Overview grouped by cluster and SID (from target-name pattern)
bin/ds_target_list.sh --overview

# Troubleshooting health overview for selected scope
bin/ds_target_list.sh --health-overview

# Health overview with drill-down details
bin/ds_target_list.sh --health-overview --health-details

# Overview for filtered scope
bin/ds_target_list.sh --overview -r "cluster1"

# Overview with status counts hidden
bin/ds_target_list.sh --overview --overview-no-status

# One-page consolidated high-level report
bin/ds_target_list.sh --report

# Equivalent explicit mode selector for consolidated report
bin/ds_target_list.sh --mode report

# Save selected target JSON payload for reuse
bin/ds_target_list.sh --all --save-json ./target_selection.json

# Run reporting from saved JSON payload (no OCI fetch)
bin/ds_target_list.sh --input-json ./target_selection.json --report

# Report includes scope banner, coverage metrics, SID impact, top SIDs, and deltas
# from previous report snapshots in ${ODB_DATASAFE_BASE}/var/

# Reuse saved payload with additional local filtering
bin/ds_target_list.sh --input-json ./target_selection.json -r "db02" --mode issues

# More list/overview/troubleshooting examples
# See: doc/quickref.md
```

### Target Management

```bash
# Refresh a specific target
bin/ds_target_refresh.sh -T mydb01

# Refresh multiple targets
bin/ds_target_refresh.sh -T db1,db2,db3

# Refresh targets where display name matches regex
bin/ds_target_refresh.sh -r "db02"

# Refresh all targets from DS_ROOT_COMP explicitly
bin/ds_target_refresh.sh --all

# Activate targets matching regex in compartment
bin/ds_target_activate.sh -c my-compartment -r "db02" --apply

# Activate all targets from DS_ROOT_COMP explicitly
bin/ds_target_activate.sh --all --apply

# Update credentials
bin/ds_target_update_credentials.sh -T mydb01

# Update credentials for all db02 targets
bin/ds_target_update_credentials.sh -r "db02" --apply

# Apply with interactive OCI confirmation (disable default force mode)
bin/ds_target_update_credentials.sh -r "db02" --apply --no-force

# Set connector for all db02 targets
bin/ds_target_update_connector.sh set --target-connector conn-prod-01 -r "db02" --apply

# Update service for all db02 targets
bin/ds_target_update_service.sh -c my-compartment -r "db02" --apply

# Update tags for all db02 targets
bin/ds_target_update_tags.sh -r "db02" --apply

# Update tags for all targets from DS_ROOT_COMP explicitly
bin/ds_target_update_tags.sh --all --apply

# Move target to different compartment
bin/ds_target_move.sh -T mydb01 -c new_compartment
```

### Service Management

```bash
# Install connector service
bin/install_datasafe_service.sh

# Uninstall all connector services
bin/uninstall_all_datasafe_services.sh
```

## For More Information

### Quick References

- 🔍 **[Tool Overview](../bin/odb_datasafe_help.sh)** - Run `./bin/odb_datasafe_help.sh` to list all available scripts
- ⚡ **[Quick Reference Guide](quickref.md)** - Command cheat sheet with examples
- 📚 **[Complete Documentation](../README.md)** - Main README with overview

### Detailed Documentation

Notes:

- `ds_target_update_credentials.sh` runs in dry-run mode by default.
- With `--apply`, OCI updates use `--force` by default for non-interactive execution.
- Use `--no-force` if you explicitly want OCI confirmation prompts.

- 🔧 **[Installation Guide](install_datasafe_service.md)** - Connector installation and setup
- 🔐 **[IAM Policies Guide](oci-iam-policies.md)** - Required OCI permissions
- 📋 **[Release Notes](release_notes/)** - Version history and migration guides
- 📝 **[CHANGELOG](../CHANGELOG.md)** - Detailed change log

### Additional Resources

All documentation is available in the **[doc/](.)** folder of this extension:

- Command references and examples
- Installation and configuration guides
- IAM policy templates
- Release notes for each version

---

**💡 Tip:** For a complete list of available tools and their purposes, run:

```bash
./bin/odb_datasafe_help.sh
```
