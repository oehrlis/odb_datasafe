# OraDBA Data Safe Extension - Standalone Usage

Use `odb_datasafe` as a standalone toolkit from its own directory, without full OraDBA workflows.

## Prerequisites

- OCI CLI installed and configured (`oci setup config`) - mandatory
- `jq` installed and available in `PATH` - mandatory
- Access to Oracle Data Safe resources
- Bash shell on Linux/macOS

## Install (Tarball)

Extract the release tarball into a dedicated folder (for example `datasafe`):

```bash
mkdir -p ~/datasafe
cd ~/datasafe
tar -xzf /path/to/odb_datasafe-<version>.tar.gz
```

## Verify Prerequisites

```bash
command -v oci >/dev/null && oci --version
command -v jq >/dev/null && jq --version
```

## Minimal Setup

```bash
cd /path/to/datasafe
cp etc/.env.example .env
vim .env
source .env

# Load Data Safe standalone shell environment
source bin/datasafe_env.sh
```

Set at least:

- `DS_ROOT_COMP` (compartment OCID or name)
- `OCI_CLI_PROFILE` (for example `DEFAULT`)

## Persist Shell Setup

Add this line to your `~/.bash_profile` so the environment is loaded
automatically for new sessions:

```bash
source /path/to/odb_datasafe/bin/datasafe_env.sh
```

## Run Commands Directly

```bash
# List targets
bin/ds_target_list.sh

# Show target details
bin/ds_target_details.sh -T mydb01

# Refresh target credentials
bin/ds_target_refresh.sh -T mydb01

# Move target to another compartment
bin/ds_target_move.sh -T mydb01 -c target_compartment

# Delete target
bin/ds_target_delete.sh -T mydb01

# Connector summary
bin/ds_target_connector_summary.sh
```

Useful flags:

- `--help` for command options
- `--dry-run` to preview actions
- `--debug` for troubleshooting
- `--format json` for automation

## Related Documentation

- Project overview: [`README.md`](../README.md)
- Command overview: [`doc/quickref.md`](quickref.md)
- Extension overview and command catalog: [`doc/index.md`](index.md)
- DB host prerequisites script: [`doc/database_prereqs.md`](database_prereqs.md)
- Connector service installation: [`doc/install_datasafe_service.md`](install_datasafe_service.md)
- OCI IAM policy requirements: [`doc/oci-iam-policies.md`](oci-iam-policies.md)
