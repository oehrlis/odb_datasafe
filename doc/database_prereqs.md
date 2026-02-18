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

Set a base directory on the DB host:

```bash
export DATASAFE_BASE="${ODB_DATASAFE_BASE:-${ORACLE_BASE}/local/datasafe}"
```

In OraDBA mode, `ODB_DATASAFE_BASE` is set automatically.

Option A (embedded payload):

```bash
scp bin/ds_database_prereqs.sh oracle@dbhost:${DATASAFE_BASE}/
ssh oracle@dbhost chmod 755 ${DATASAFE_BASE}/ds_database_prereqs.sh
```

Option B (external SQL files):

```bash
scp bin/ds_database_prereqs.sh sql/*.sql oracle@dbhost:${DATASAFE_BASE}/
ssh oracle@dbhost chmod 755 ${DATASAFE_BASE}/ds_database_prereqs.sh
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
${DATASAFE_BASE}/ds_database_prereqs.sh --root -P "<password>"
```

With embedded SQL:

```bash
${DATASAFE_BASE}/ds_database_prereqs.sh --root --embedded -P "<password>"
```

### Single PDB

```bash
${DATASAFE_BASE}/ds_database_prereqs.sh --pdb APP1PDB -P "<password>"
```

### Root + all open PDBs

```bash
${DATASAFE_BASE}/ds_database_prereqs.sh --all -P "<password>"
```

## Check-Only Mode

Validate user and grants without applying changes:

```bash
${DATASAFE_BASE}/ds_database_prereqs.sh --root --check
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

## Secret Handling

Secret resolution order:

1. `--ds-password`
2. `--password-file`
3. `<user>_pwd.b64` in `ORADBA_ETC`, `ODB_DATASAFE_BASE/etc`, or current dir
4. Auto-generate and write `<user>_pwd.b64`

`--ds-password` accepts either a plain-text secret or a base64-encoded value.
If the value looks like valid base64, the script decodes it before use.

Example (base64 input):

```bash
DS_PW_B64=$(printf '%s' 'mySecret' | base64)
${DATASAFE_BASE}/ds_database_prereqs.sh --root -P "${DS_PW_B64}"
```

Example (pre-create secret file used by auto-discovery):

```bash
mkdir -p "${ODB_DATASAFE_BASE}/etc"
printf '%s' 'mySecret' | base64 > "${ODB_DATASAFE_BASE}/etc/DS_ADMIN_pwd.b64"
chmod 600 "${ODB_DATASAFE_BASE}/etc/DS_ADMIN_pwd.b64"

# Script will discover and use DS_ADMIN_pwd.b64 automatically
${DATASAFE_BASE}/ds_database_prereqs.sh --root --ds-user DS_ADMIN
```

Example (generate random secret and store as base64 file):

```bash
mkdir -p "${ODB_DATASAFE_BASE}/etc"
RAND_SECRET=$(openssl rand -base64 24 | tr -d '\n')
printf '%s' "${RAND_SECRET}" | base64 > "${ODB_DATASAFE_BASE}/etc/DS_ADMIN_pwd.b64"
chmod 600 "${ODB_DATASAFE_BASE}/etc/DS_ADMIN_pwd.b64"

${DATASAFE_BASE}/ds_database_prereqs.sh --root --ds-user DS_ADMIN
```

## User Management Behavior

- **Create if missing**: default behavior when the user does not exist.
- **Update profile only**: default behavior when the user exists (no secret change).
- **Update secret (no drop)**: use `--update-secret` to set a new secret while
  keeping the user and grants.
- **Drop and recreate**: use `--force` to drop and recreate the user.

Examples:

```bash
# Update profile only (user exists)
${DATASAFE_BASE}/ds_database_prereqs.sh --root -P "<secret>"

# Update secret without dropping the user
${DATASAFE_BASE}/ds_database_prereqs.sh --root -P "<secret>" --update-secret

# Drop and recreate the user
${DATASAFE_BASE}/ds_database_prereqs.sh --root -P "<secret>" --force
```

## Notes

- The script assumes the database environment is already configured.
- Use `--force` to drop and recreate the Data Safe user when needed.
- `create_ds_admin_prerequisites.sql` accepts the profile name as parameter 1.
- `create_ds_admin_user.sql` updates the profile only when `FORCE` is FALSE to avoid ORA-28007.
- If you see an ORA-28007 reuse warning, use a different secret or rerun with `--force`.

## Updating the Embedded Payload

If you update the SQL scripts, rebuild the embedded payload in the script.

Simple helper script:

```bash
./scripts/update_embedded_payload.sh
```

Manual method:

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

  in_payload && /^__PAYLOAD_END__$/ {
    in_payload=0
    next
  }

  in_payload { next }
  { print }
' bin/ds_database_prereqs.sh > /tmp/ds_database_prereqs.sh || exit 1

mv /tmp/ds_database_prereqs.sh bin/ds_database_prereqs.sh
chmod 755 bin/ds_database_prereqs.sh

# Optional sanity check
bin/ds_database_prereqs.sh --help >/dev/null
```
