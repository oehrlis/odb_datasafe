# On-Prem Database Prerequisites

This guide shows how to configure an on-premises Oracle database for Data Safe
using `ds_database_prereqs.sh`. The script runs locally on the database host and
executes SQL*Plus as SYSDBA, so the Oracle environment must be sourced before
running it.

## Requirements

- `ds_database_prereqs.sh` available on the DB host
- SQL files available on the DB host (unless using `--embedded`):
  - `create_ds_admin_prerequisites.sql`
  - `create_ds_admin_user.sql`
  - `datasafe_privileges.sql`
- `ORACLE_HOME` and `ORACLE_SID` configured (for example with `oraenv`)
- `sqlplus` available in the environment

## Copy Files to the DB Host

Option A (embedded payload):

```bash
scp bin/ds_database_prereqs.sh oracle@dbhost:/opt/datasafe/
ssh oracle@dbhost chmod 755 /opt/datasafe/ds_database_prereqs.sh
```

Option B (external SQL files):

```bash
scp bin/ds_database_prereqs.sh sql/*.sql oracle@dbhost:/opt/datasafe/
ssh oracle@dbhost chmod 755 /opt/datasafe/ds_database_prereqs.sh
```

## Source the Oracle Environment

```bash
export ORACLE_SID=cdb01
. oraenv <<< "${ORACLE_SID}" >/dev/null
```

Alternative environment loaders:

- Trivadis `basenv`
- `dbstar`
- OraDBA environment loader

## Run the Prereqs

### CDB$ROOT only

```bash
/opt/datasafe/ds_database_prereqs.sh --root -P "<password>"
```

With embedded SQL:

```bash
/opt/datasafe/ds_database_prereqs.sh --root --embedded -P "<password>"
```

### Single PDB

```bash
/opt/datasafe/ds_database_prereqs.sh --pdb APP1PDB -P "<password>"
```

### Root + all open PDBs

```bash
/opt/datasafe/ds_database_prereqs.sh --all -P "<password>"
```

## Check-Only Mode

Validate user and grants without applying changes:

```bash
/opt/datasafe/ds_database_prereqs.sh --root --check
```

## Drop User Only

Drop the Data Safe user while keeping the profile intact:

```bash
/opt/datasafe/ds_database_prereqs.sh --root --drop-user
```

Scope options work the same as prereqs:

```bash
/opt/datasafe/ds_database_prereqs.sh --pdb APP1PDB --drop-user
/opt/datasafe/ds_database_prereqs.sh --all --drop-user
```

## User Naming Behavior

- Root scope always uses a common user with `C##` prefix.
- PDB scope always uses a local user without `C##` prefix.

Examples:

- `--ds-user C##DS_ADMIN1`
  - Root: `C##DS_ADMIN1`
  - PDB : `DS_ADMIN1`
- `--ds-user DS_ADMIN2`
  - Root: `C##DS_ADMIN2`
  - PDB : `DS_ADMIN2`

## Password Handling

Password resolution order:

1. `--ds-password`
2. `--password-file`
3. `<user>_pwd.b64` in `ORADBA_ETC`, `ODB_DATASAFE_BASE/etc`, or current dir
4. Auto-generate and write `<user>_pwd.b64`

## Notes

- The script assumes the database environment is already configured.
- Use `--force` to drop and recreate the Data Safe user when needed.
- `create_ds_admin_prerequisites.sql` accepts the profile name as parameter 1.
- `create_ds_admin_user.sql` updates the profile only when `FORCE` is FALSE to avoid ORA-28007.

## Updating the Embedded Payload

If you update the SQL scripts, rebuild the embedded payload in the script.

```bash
ZIP_FILE="$(mktemp -t ds_sql.XXXXXX).zip"
PAYLOAD_B64="$(mktemp -t ds_sql.XXXXXX).b64"

zip -j "$ZIP_FILE" \
  sql/create_ds_admin_prerequisites.sql \
  sql/create_ds_admin_user.sql \
  sql/datasafe_privileges.sql

base64 "$ZIP_FILE" > "$PAYLOAD_B64"

awk -v payload="$PAYLOAD_B64" '
  /^__PAYLOAD_BEGINS__$/ {
    print
    print ": <<'\''__PAYLOAD_END__'\''"
    while ((getline line < payload) > 0) print line
    close(payload)
    print "__PAYLOAD_END__"
    in_payload=1
    next
  }
  in_payload { next }
  { print }
' bin/ds_database_prereqs.sh > /tmp/ds_database_prereqs.sh

mv /tmp/ds_database_prereqs.sh bin/ds_database_prereqs.sh
chmod 755 bin/ds_database_prereqs.sh
```
