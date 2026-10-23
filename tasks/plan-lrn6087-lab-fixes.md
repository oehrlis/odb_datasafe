# Plan - fixes found on the LRN6087 lab (2026-10-23)

Context: building the LRN6087 demo lab (oci-labs `datasafe-demo`, 26ai 23.26.4 + 19c, ON_PREMISES via on-prem
connector) on 2026-10-22/23 surfaced seven defects in odb_datasafe 1.3.1. Number 1 is fixed on `main` already, the
others are open. Goal: fix all with tests, release 1.3.2. Open tasks are also listed in `tasks/todo.md`
("Open - found on the LRN6087 lab").

## 1. CONTAINER=ALL on CREATE PROFILE (fixed, verify and test)

`sql/create_ds_admin_prerequisites.sql` appended `CONTAINER=ALL` to `CREATE PROFILE` since v0.22.0. In every PDB
this raises ORA-65140 (invalid common profile name), so `--all` and `--pdb` created no local `DS_ADMIN`. Fix on
`main`: the clause only when `SYS_CONTEXT('USERENV','CON_NAME') = 'CDB$ROOT'`. Verified on the lab (CDB19 and
CDB26, root plus two PDBs each). Still to check: non-CDB (CON_NAME is the DB name there - no clause, correct), the
ALTER branch needs no clause. Add a test.

## 2. Silent success in bin/ds_database_prereqs.sh

With ORA-28003 in `create_ds_admin_user.sql` (secret without a special character vs. `ORA12C_VERIFY_FUNCTION`) and
the follow-up ORA-44001 in the grants the script printed `Done` and returned rc 0 - no user, but success. Check:

- `sql/create_ds_admin_user.sql:74` `WHENEVER SQLERROR CONTINUE` after the create block
- `run_sql_local` (~line 1039): in the `--debug` path `sqlplus | tee` returns the status of `tee`
- `sql/datasafe_privileges.sql` catches ORA-44001 and only prints text

Expected: a scope fails (rc != 0, ERROR with scope and ORA code) when user creation or grants fail; `--all`
continues with the remaining scopes and ends with rc != 0 and a summary. Rule: a filter or skip that holds back
silently is a defect - every exception is named.

## 3. Check the secret before CREATE USER

Check the secret against the verify function of the profile (PL/SQL with `ORA12C_VERIFY_FUNCTION` in the target
container) or turn ORA-28003 into a message that names the rule ("at least one special character"). Secret never
in argv, never in a log; SQL via stdin or a 0600 temp file.

## 4. Connector bundle password via file:// (lib/ds_lib.sh:1474)

`--password "file://$pwd_file"`: the OCI CLI does not expand `file://` for this string option and sends the path
as the password -> 400 InvalidParameter "Invalid input". Worked on the lab: `--from-json file://<json>` with
`onPremConnectorId`, `password`, `file` (skeleton:
`oci data-safe on-prem-connector generate-on-prem-connector-configuration --generate-full-command-json-input`).
JSON file with umask 077, built with `jq --arg`, trap cleanup. The bundle password also needs a special character
(otherwise also "Invalid input") - ensure it where `ds_connector_create.sh` generates one. `echo "$password"` writes
a trailing newline - use `printf '%s'`. Check all callers (`ds_connector_create.sh`, `ds_connector_update.sh`).

## 5. ds_target_register.sh swallows the OCI error

On 400 LimitExceeded ("The limit for this tenancy has been exceeded") the output was only
`OCI command failed (exit 1)`, `Registration failed` and an empty ERROR line. Print `code` and `message` of the
OCI response (`oci_exec` / `register_target`). Check other `oci_exec` callers for the same pattern.

## 6. ds_target_register.sh -n demands the secret

`ds_target_register.sh ... -n` stops with `Missing required option: --ds-secret (not needed with --check)`. A dry
run only prints the plan and the masked payload - it must not need the secret. Workaround in oci-labs `demo.sh`:
the secret file is passed in both modes.

## 7. Target-list file cache is not invalidated by a registration

`ds_lib.sh` caches the target list per compartment in a file (`DS_TARGET_CACHE_TTL`). The existence check of
`ds_target_register.sh` filled the cache before the new target existed; `ds_target_audit_trail.sh -T <new target>`
30 s later used that cache and failed with `Target not found` (debug: `Using cached target list ... [file]
age=153s`). Invalidate the cache for the compartment after create/delete of a target (register, delete, reset);
when a name is not found in a cached list, refresh once before giving up. Workaround in the demo copy:
`DS_TARGET_CACHE_TTL="0"`.

## Approach

- [ ] Extend this plan / `tasks/todo.md` first, then implement
- [ ] Bats tests: 2 (rc != 0 on SQL error, sqlplus mock), 6 (-n without secret), 7 (cache refresh),
  4 (oci mock checks `--from-json`, no `--password` and no
  secret in argv), 5 (error code and message printed)
- [ ] `make test` and `make lint-ci` green
- [ ] CHANGELOG `[Unreleased]` -> Fixed (entry for 1 exists), bump to 1.3.2
- [ ] Conventional Commits, no Co-Authored-By, check the branch before every commit
- [ ] Release: agree with Stefan before `make tag`; push the tag, check the release asset and its `.sha256`
- [ ] oci-labs (worktree `~/Repos/own/oehrlis/oci-labs-datasafe-demo`, branch `feat/datasafe-demo`):
  `odb_datasafe_version` / `odb_datasafe_sha256` in `terraform/envs/datasafe-demo/variables.tf` to 1.3.2 (sha from
  the asset, never guessed), runbook `docs/datasafe-demo.md` (laptop copy, checksum). The lab host (Trivadis
  tenancy) runs 1.3.1 with the fixed SQL copied in by hand; pull it to 1.3.2 with
  `make dsdemo-step TAG=odb_datasafe DSDEMO_LOCAL_PORT=2223` - coordinate with the LRN6087 session, the demo runs
  on that host
