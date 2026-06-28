# Oracle SQL and Audit Policy Findings - odb_datasafe v0.20.4

**Scope:** 6 SQL scripts, bin/ds_database_prereqs.sh, doc/database_prereqs.md, doc/oci-iam-policies.md

---

## Findings

### ORA-001 - Template password `DS_Admin.2025` hardcoded as default in source

- **Severity:** Critical
- **Standard:** CIS 1.x / STIG / OraDBA core-invariants (no hardcoded credentials)
- **Evidence:** `sql/create_ds_admin_user.sql:40` - `DEFINE _ds_passwd = 'DS_Admin.2025'`
- **Issue:** A real, policy-compliant password is committed to the repo as the default value for
  `&_ds_passwd`. If the script is run without an explicit password argument, the Data Safe admin
  user is created with this publicly known, in-repo password. Committed to a public GitHub repo
  so it is a known-credential for any deployment that did not override it.
- **Recommendation:** Replace the default with an empty string and make the script fail fast when
  `&2` is empty. The shell wrapper always passes `${DATASAFE_PASS}` so the SQL default is never
  needed operationally - set it to `''`. Purge the literal from history.

---

### ORA-002 - Password passed as positional SQL*Plus argument - exposure via process table and logs

- **Severity:** High
- **Standard:** STIG / CIS (credential handling)
- **Evidence:** `bin/ds_database_prereqs.sh:1232` builds `@"...create_ds_admin_user.sql" DS_ADMIN
  <password> ...`; temp SQL written to `${TMPDIR:-/tmp}` (`build_temp_sql_script:916`);
  `create_ds_admin_user.sql:59` assigns `&2` into `&ds_passwd`. With `SET ECHO ON` under `--debug`
  the substituted value surfaces in spool/log.
- **Recommendation:** Do not run create_ds_admin_user.sql with `set echo on`. Restrict temp script
  perms (`chmod 600` after mktemp). Drop unconditional `SPOOL create_ds_admin_user.log` or route
  to mode-0600 location. Prefer Oracle `ACCEPT ... HIDE` or bind-variable mechanism.

---

### ORA-003 - Profile `DS_USER_PROFILE` weakens security vs. CIS (short lockout, unlimited idle)

- **Severity:** High
- **Standard:** CIS Oracle 19c 5.2.x (profile/password limits)
- **Evidence:** `sql/create_ds_admin_prerequisites.sql:32-50` (CREATE) and `53-71` (ALTER)
- **Issue:** Key deviations from CIS:
  - `PASSWORD_LOCK_TIME 299/86400` ~5 min. CIS expects `PASSWORD_LOCK_TIME = 1` (1 day).
    Effectively neuters lockout against brute force.
  - `INACTIVE_ACCOUNT_TIME DEFAULT` - CIS wants finite (e.g. 35 days).
  - `SESSIONS_PER_USER`, `IDLE_TIME`, `CONNECT_TIME` all `UNLIMITED`.
  - `PASSWORD_VERIFY_FUNCTION ORA12C_VERIFY_FUNCTION` - acceptable but not the strongest
    (CIS prefers `ORA12C_STRONG_VERIFY_FUNCTION`).
- **Recommendation:** Set `PASSWORD_LOCK_TIME 1`, set `INACTIVE_ACCOUNT_TIME` to a finite value.
  Document explicitly which CIS controls are intentionally relaxed for the service account.

---

### ORA-004 - Profile creation does not specify CDB vs. PDB scope / common-profile semantics

- **Severity:** Medium
- **Standard:** OraDBA core-invariants (explicit CDB/PDB scope), Oracle 19c multitenant
- **Evidence:** `sql/create_ds_admin_prerequisites.sql:32` - `CREATE PROFILE ... LIMIT`, no
  `CONTAINER` clause. Shell resolves `C##`-prefixed profile name for ROOT
  (`bin/ds_database_prereqs.sh:1176-1192`).
- **Issue:** `CREATE PROFILE` in CDB$ROOT without `CONTAINER=ALL` creates the profile only in
  root. A `C##DS_ADMIN` user in PDBs may reference a profile that does not exist there.
- **Recommendation:** For ROOT: create profile with `CONTAINER=ALL` so PDBs inherit it.
  Add post-create verification `SELECT` against `cdb_profiles` with `con_id`.

---

### ORA-005 - `GRANT CONNECT, RESOURCE` to DS admin user - RESOURCE is broader than needed

- **Severity:** Medium
- **Standard:** CIS 5.1.x (least privilege), STIG
- **Evidence:** `sql/create_ds_admin_user.sql:145`, repeated at `:153`
- **Issue:** `RESOURCE` carries object-creation system privileges and historically
  `UNLIMITED TABLESPACE`. For an account that primarily needs `CREATE SESSION` plus
  `ORA_DSCS_*` feature roles, `RESOURCE` is excess privilege.
- **Recommendation:** Grant only `CREATE SESSION` here; let `datasafe_privileges.sql` add
  feature-specific roles. Grant explicit tablespace quota if needed rather than via RESOURCE.

---

### ORA-006 - Broad `ANY`/system privileges granted by MASKING and DATA_DISCOVERY modes

- **Severity:** Medium (informational - vendor script)
- **Standard:** CIS 5.1.x (ANY privileges), STIG
- **Evidence:** `sql/datasafe_privileges.sql:1200-1207` (MASKING grants `SELECT ANY TABLE`,
  `CREATE/DROP/ALTER ANY TABLE/PROCEDURE`, `ALTER SYSTEM`, etc.);
  `sql/datasafe_privileges.sql:865` (DATA_DISCOVERY grants `READ/SELECT ANY TABLE`)
- **Issue:** These are Oracle's official prerequisite grants, but `--grant-mode ALL` (the
  default) grants the full superset including MASKING + DATA_DISCOVERY for every registration.
- **Recommendation:** Do not modify the vendor script. Change the wrapper default `DS_GRANT_MODE`
  from `ALL` to a least-privilege set (e.g. `ASSESSMENT,AUDIT_COLLECTION,AUDIT_SETTING`).

---

### ORA-007 - `--grant-mode ALL` is the default - over-provisioning by default

- **Severity:** Medium
- **Standard:** Least privilege (CIS/STIG/BP)
- **Evidence:** `bin/ds_database_prereqs.sh:424` - `: "${DS_GRANT_MODE:=ALL}"`; consumed at `:1233`
- **Issue:** The default registration path grants every Data Safe feature role, violating least
  privilege.
- **Recommendation:** Default to the minimal viable mode for registration; require operators to
  opt into MASKING/DATA_DISCOVERY/SQL_FIREWALL explicitly.

---

### ORA-008 - No `AUDIT POLICY` / `NOAUDIT POLICY` statements - verified clean

- **Severity:** Low (informational)
- **Standard:** OraDBA core-invariant "pair AUDIT with NOAUDIT"
- **Evidence:** `grep 'AUDIT POLICY|NOAUDIT POLICY' sql/*.sql` returns nothing.
- **Issue:** No unified audit policies defined. The GRANT/REVOKE pairing invariant is satisfied
  (grant paths have corresponding REVOKE branches).
- **Recommendation:** No action required. If `AUDIT POLICY` statements are added in future,
  ensure each has a matching `NOAUDIT POLICY` cleanup.

---

### ORA-009 - `HOST echo`/`HOST rm` with shell variable interpolation in extension_comprehensive.sql

- **Severity:** Medium
- **Standard:** SQL injection / command injection hygiene
- **Evidence:** `sql/extension_comprehensive.sql:43-45`

```sql
HOST echo "DEFINE LOGDIR = '${ORADBA_LOG:-.}'" > /tmp/oradba_logdir_${USER}.sql ...
@@/tmp/oradba_logdir_${USER}.sql
HOST rm -f /tmp/oradba_logdir_${USER}.sql
```

- **Issue:** Predictable, world-readable-path temp file. If `ORADBA_LOG` contains a single quote
  or shell metacharacters, the generated DEFINE line can inject arbitrary SQL*Plus directives.
- **Recommendation:** Replace HOST round-trip with `COLUMN ... NEW_VALUE` from
  `SYS_CONTEXT('USERENV', ...)`. If HOST is unavoidable, use `mktemp` and validate/escape
  `ORADBA_LOG`.

---

### ORA-010 - extension_simple.sql / extension_query.sql: v$database/v$instance cartesian join

- **Severity:** Low
- **Standard:** Correctness (Oracle 19c multitenant / RAC)
- **Evidence:** `sql/extension_simple.sql:39-40`, `sql/extension_query.sql:23-27`
- **Issue:** `FROM v$database d, v$instance i` with no join predicate. Works on single-instance
  (one row each), but on RAC `gv$instance` would be needed for cluster-wide data. Scope not stated.
- **Recommendation:** No security action. Optionally note RAC/multitenant scope in the header.

---

### ORA-011 - `WHENEVER SQLERROR EXIT` without FAILURE in datasafe_privileges.sql

- **Severity:** Low
- **Standard:** Correctness / error propagation
- **Evidence:** `sql/datasafe_privileges.sql:37` - `WHENEVER SQLERROR EXIT;`
- **Issue:** Without `FAILURE` keyword, exits with success status on SQL error. The shell wrapper
  injects its own `whenever sqlerror exit failure`, mitigating this in the integrated path.
- **Recommendation:** Rely on the wrapper's injected directive. Verify it remains in place.
  Vendor file - do not modify.

---

### ORA-012 - create_ds_admin_user.sql WHEN OTHERS handler: silent password-unchanged on ORA-28007

- **Severity:** Low
- **Standard:** Correctness
- **Evidence:** `sql/create_ds_admin_user.sql:148-158`
- **Issue:** On ORA-28007 (password reuse) the user is created/altered with old password silently.
  Shell wrapper warns (`ds_database_prereqs.sh:1016`). Behavior is documented
  (`doc/database_prereqs.md:170-171`).
- **Recommendation:** No action; behavior is documented. Ensure operator message clearly states
  the secret was NOT changed.

---

### ORA-013 - OCI IAM policies use `manage data-safe-family in tenancy` - over-broad

- **Severity:** High
- **Standard:** Least privilege (BP / OCI IAM best practice)
- **Evidence:** `doc/oci-iam-policies.md:118` (`Allow group grp-ds-admin to manage
  data-safe-family in tenancy`), `:236` (`Allow group grp-ds-service to manage data-safe-family
  in tenancy`)
- **Issue:** Tenancy-wide `manage` contradicts the document's own "Least Privilege" principles.
  The JSON example at `:370` correctly constrains with `where target.compartment.id = ...` but
  the prose body does not - internal inconsistency means readers copy the unconstrained form.
- **Recommendation:** Remove bare `... in tenancy` manage statements or constrain with `where`
  clause as the JSON example does. Use `compartment-id-in-subtree` for cross-compartment needs.

---

### ORA-014 - Service account granted `use keys` and broad tenancy reads

- **Severity:** Medium
- **Standard:** Least privilege (BP)
- **Evidence:** `doc/oci-iam-policies.md:262` (`grp-ds-service ... use keys`),
  `:250-255` multiple `read ... in tenancy`
- **Issue:** Service automation group can `use keys` (cryptographic operations) and read
  database-family/network across the whole tenancy. Labeled "for future credential retrieval" -
  not yet used.
- **Recommendation:** Drop `use keys` from service group until a concrete use case exists. Scope
  `read` statements to specific compartment subtree.

---

### ORA-015 - `--ds-user` and `--pdb` interpolated unquoted into dynamic SQL

- **Severity:** Low
- **Standard:** SQL injection hygiene
- **Evidence:** `bin/ds_database_prereqs.sh:1265-1271` (check SQL interpolates `${ds_user}`),
  `:1298-1300` (drop SQL), `:937` (`alter session set container=${PDB}` unquoted),
  `:1103` (`upper('${pdb_name}')`)
- **Issue:** `ds_user` derives from `--ds-user` and `PDB` from `--pdb`, interpolated into
  SQL*Plus heredocs without identifier whitelisting. PDB names are validated at `:1086` but
  `--ds-user` is not validated against an identifier allowlist before use in drop/check SQL.
  Both run as SYSDBA.
- **Recommendation:** Validate `DATASAFE_USER` and each PDB against strict identifier regex
  (`^[A-Za-z0-9_$#]+$`, plus optional `C##` prefix) in `validate_inputs` before SQL construction.

---

### ORA-016 - Data Safe prerequisite implementation is functionally correct (positive finding)

- **Severity:** Low (positive)
- **Standard:** Oracle Data Safe on-prem connector prerequisites
- **Evidence:** `sql/datasafe_privileges.sql` is the unmodified Oracle-supplied script;
  `bin/ds_database_prereqs.sh:1233` invokes it with correct parameters.
- **Issue:** The prerequisite logic correctly implements Data Safe connector prerequisites with
  REVOKE paths, DV awareness, and container detection.
- **Recommendation:** Keep `datasafe_privileges.sql` unmodified. Track upstream version for
  Oracle updates.

---

## AUDIT/NOAUDIT Pair Inventory

| Statement type | AUDIT location | NOAUDIT/cleanup location | Status |
|---|---|---|---|
| `AUDIT POLICY` (unified) | none | none | n/a - no unified audit policies defined |
| Audit privilege grants | `datasafe_privileges.sql:359, 386-387, 401` | REVOKE branches via `--grant-type REVOKE` | Paired |
| DV audit authorizations | `datasafe_privileges.sql:444, 519` | `UNAUTHORIZE_*` at `:527-541` | Paired |

**Conclusion:** No unpaired AUDIT/NOAUDIT statements. Core invariant satisfied.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID     | Severity | Area                          | One-line                                                              |
|--------|----------|-------------------------------|-----------------------------------------------------------------------|
| ORA-001 | Critical | Credentials                   | Hardcoded default password `DS_Admin.2025` in SQL source              |
| ORA-002 | High     | Credentials                   | DB password passed as positional SQL*Plus arg, appears in process list |
| ORA-003 | High     | Profile/CIS                   | `PASSWORD_LOCK_TIME` 5 min vs. CIS requirement of 1 day               |
| ORA-013 | High     | OCI IAM                       | `manage data-safe-family in tenancy` grants over-broad                 |
| ORA-004 | Medium   | Multitenant                   | Profile created without explicit `CONTAINER` scope in CDB              |
| ORA-005 | Medium   | Least privilege               | `GRANT RESOURCE` over-broad for a service/admin account                |
| ORA-006 | Medium   | Vendor script / ANY privs     | `--grant-mode ALL` default activates MASKING/DATA_DISCOVERY ANY grants |
| ORA-007 | Medium   | Least privilege               | `DS_GRANT_MODE=ALL` is the default; should be minimal viable mode      |
| ORA-009 | Medium   | SQL injection                 | HOST + predictable /tmp path in extension_comprehensive.sql            |
| ORA-014 | Medium   | OCI IAM                       | Service account has `use keys` and tenancy-wide reads not yet needed   |
| ORA-008 | Low      | Audit pairing                 | Verified: no unpaired AUDIT/NOAUDIT statements (positive)              |
| ORA-010 | Low      | Correctness                   | v$database / v$instance cartesian join in extension templates          |
| ORA-011 | Low      | Correctness                   | Vendor script WHENEVER SQLERROR without FAILURE                        |
| ORA-012 | Low      | Correctness                   | Silent password-unchanged on ORA-28007 is documented                   |
| ORA-015 | Low      | SQL injection                 | `--ds-user` / `--pdb` not whitelisted before inline SQL construction   |
| ORA-016 | Low      | Positive                      | Vendor datasafe_privileges.sql unmodified and correctly invoked        |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** Critical: 1, High: 3, Medium: 6, Low: 6
