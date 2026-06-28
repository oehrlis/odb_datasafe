# Security Findings - odb_datasafe v0.20.4

**Scope:** lib/common.sh, lib/oci_helpers.sh, bin/install_datasafe_service.sh,
bin/uninstall_all_datasafe_services.sh, bin/ds_target_register.sh,
bin/ds_target_update_credentials.sh, etc/datasafe.conf.example, sql/create_ds_admin_user.sql,
.github/workflows/ci.yml, .github/workflows/release.yml

---

## Findings

### SEC-001 - Hardcoded default password in SQL admin-user creation script

- **Severity:** High
- **Category:** CWE-798 (Hard-coded Credentials) / CWE-1392 (Default Credentials)
- **Evidence:** `sql/create_ds_admin_user.sql:40` - `DEFINE _ds_passwd = 'DS_Admin.2025'`. Used
  at lines 107, 115, 124, 138 in `CREATE USER ... IDENTIFIED BY "&ds_passwd"` /
  `ALTER USER ... IDENTIFIED BY "&ds_passwd"`.
- **Exploit:** Committed to a public GitHub repo - a known credential for any deployment that did
  not explicitly override it. Running `@create_ds_admin_user.sql DS_ADMIN` without an explicit
  password creates the privileged Data Safe admin user with this publicly known password.
- **Recommendation:** Remove the hardcoded default. Fail hard when `&2` is empty. Rotate any
  deployed `DS_Admin.2025` accounts.

---

### SEC-002 - DB secret passed as command-line argument (visible in process list)

- **Severity:** High
- **Category:** CWE-214 (Visible Sensitive Information in Process) / CWE-200
- **Evidence:** `bin/ds_target_register.sh:277-280` (`-P | --ds-secret`);
  `bin/ds_target_update_credentials.sh:246-250` (same). Both documented as primary usage.
- **Exploit:** On a shared server any local user can run `ps -ef` while the script runs and read
  the plaintext DB password. Also exposed in shell history and process accounting.
- **Recommendation:** Emit a `log_warn` when `-P/--ds-secret` is used on the command line.
  Steer users to `--secret-file`, env var, interactive `read -rs`, or `--cred-file`. Safer paths
  already exist in the codebase.

---

### SEC-003 - Bundle password on OCI CLI command line (process list exposure)

- **Severity:** Medium
- **Category:** CWE-214
- **Evidence:** `ds_generate_connector_bundle` (`lib/oci_helpers.sh:2129-2132`) passes
  `--password "$password"` to `oci`. The wrapper `_oci_redact_cmd` masks `--password` in logs,
  but the value appears in live `oci` process args.
- **Recommendation:** Pass connector/bundle secrets via file (`file://`) rather than `--password`
  on argv, mirroring the `--credentials file://` pattern already used for target credentials.

---

### SEC-004 - Temp credential files may have default umask; register payload uses predictable path

- **Severity:** Medium
- **Category:** CWE-377 (Insecure Temporary File) / CWE-276 (Incorrect Default Permissions)
- **Evidence:** `bin/ds_target_register.sh:1109` writes full registration payload (including
  plaintext `credentials.password` at `:1167`) to `${TMPDIR:-/tmp}/ds_target_<name>.json` -
  a predictable non-`mktemp` path. On failure this file is deliberately preserved
  (`install_datasafe_service.sh:1212` "Keeping failed registration payload").
- **Recommendation:** Use `mktemp` for the register payload (instead of predictable name).
  Set `umask 077` before creating or `chmod 600` immediately after. On failure, redact the
  password before persisting (write `****` copy, delete the real one). Add EXIT trap.

---

### SEC-005 - Config files sourced without ownership/permission checks

- **Severity:** Medium
- **Category:** CWE-426 (Untrusted Search Path) / CWE-94
- **Evidence:** `lib/common.sh:469-531` (`load_config`/`init_config`) `source`s
  `${ODB_DATASAFE_BASE}/.env`, `${ORADBA_ETC}/datasafe.conf`, etc. `ORADBA_ETC` is taken from
  environment unchecked. No ownership/permission check before sourcing.
- **Exploit:** If config directory is writable by a less-privileged user and a script is run by
  root (via installer flow), attacker can inject arbitrary bash into `datasafe.conf`.
- **Recommendation:** Before `source`, verify config file and directory are owned by root or
  invoking user and not group/world writable. Reject otherwise with clear error. Document that
  config dirs must not be writable by untrusted users.

---

### SEC-006 - Installer auto-regenerates files as root, broad `chown` with masked failure

- **Severity:** Medium
- **Category:** CWE-732 (Incorrect Permission Assignment) / CWE-269
- **Evidence:** `bin/install_datasafe_service.sh:927-937` - `--install` silently calls
  `prepare_service` again on User= mismatch, then `chown "${OS_USER}:${OS_GROUP}"
  "${CONNECTOR_ETC}"/*` (`:934`) with `|| true` masking failures. Broad wildcard chown.
- **Recommend:** Generate root-owned files in root-only temp dir (`mktemp -d`, mode 700).
  Validate sudoers with `visudo -c` before copying. Use `install -o root -g root -m 440`
  directly to `/etc/sudoers.d/`. Do not mask chown failure with `|| true`.

---

### SEC-007 - Generated sudoers grants `journalctl` with trailing wildcard

- **Severity:** Medium
- **Category:** CWE-250 (Unnecessary Privileges)
- **Evidence:** `bin/install_datasafe_service.sh:630` - sudoers rule ends with
  `NOPASSWD: /bin/journalctl -u $SERVICE_NAME*` (trailing `*` glob). Also hardcodes
  `/bin/systemctl` (path may differ by distro).
- **Recommendation:** Drop the trailing `*` on the journalctl rule (pin to exact unit or
  use `--unit=` exact form). Verify systemctl/journalctl absolute paths per-distro.

---

### SEC-008 - Force-kill by path pattern (`pkill -f`) during uninstall

- **Severity:** Low
- **Category:** CWE-697 / unintended process termination
- **Evidence:** `bin/uninstall_all_datasafe_services.sh:229-234` -
  `pgrep -f "${cman_bin}"` / `pkill -f "${cman_bin}"`. Any process whose command line
  contains the substring would be killed when running as root.
- **Recommendation:** Match more precisely (anchor to executable). Prefer stopping via registry
  path that the code already tries first.

---

### SEC-009 - `set -euo pipefail` absent in most entry scripts; widespread `|| true` masking

- **Severity:** Low
- **Category:** CWE-754 (Improper Check for Unusual Conditions)
- **Evidence:** ~39 scripts lack `set -euo pipefail` (per static scan). Numerous `|| true` on
  OCI/chown/stop paths: `bin/install_datasafe_service.sh:934,1002`;
  `bin/uninstall_all_datasafe_services.sh:220,227,233`; `lib/oci_helpers.sh:477,483,520`.
- **Recommendation:** Add `set -euo pipefail` immediately after shebang in all entry scripts.
  Audit each `|| true` on credential/compartment resolution paths to ensure empty result
  fails closed.

---

### SEC-010 - Secret may be written to configured log file

- **Severity:** Low
- **Category:** CWE-532 (Sensitive Information in Log File)
- **Evidence:** `lib/common.sh:159-161` - `log()` appends to `LOG_FILE` unredacted.
  `_oci_redact_cmd` only masks the token following `--password` - does not mask
  `--credentials` values or any future flag carrying a secret. `ds_refresh_target`
  captures `oci ... 2>&1` (`lib/oci_helpers.sh:1660`) and writes raw output to `LOG_FILE`.
- **Recommendation:** Document/enforce restrictive permissions on `LOG_FILE` (create 600).
  Broaden `_oci_redact_cmd` to also mask `--credentials`, `--secret`, `--auth-token`.

---

## Positive Observations

- OCI target-credential update uses `--credentials file://<mktemp>` rather than passing password
  on argv, with an EXIT cleanup trap (`ds_target_update_credentials.sh:520,592,640`).
- `--password` is redacted in all logged OCI command strings (`_oci_redact_cmd`,
  `lib/oci_helpers.sh:293`).
- Interactive secret entry uses `read -rs` (no echo) and writes prompt to stderr
  (`ds_target_update_credentials.sh:499-501`).
- `jq` is used with `--arg` for all user-influenced values in query payloads.
- Bundle key generation uses `openssl rand` with complexity enforcement
  (`lib/oci_helpers.sh:2180-2213`).
- CI/CD uses only auto-provisioned `secrets.GITHUB_TOKEN` with scoped `contents: write`.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID     | Severity | Area                     | One-line                                                                   |
|--------|----------|--------------------------|----------------------------------------------------------------------------|
| SEC-001 | High    | Credentials              | Hardcoded default password `DS_Admin.2025` in SQL script                  |
| SEC-002 | High    | Credentials              | `-P/--ds-secret` exposes DB password in process list                       |
| SEC-003 | Medium  | Credentials              | Bundle password on OCI CLI argv, readable via `ps`                         |
| SEC-004 | Medium  | Temp files               | Register payload uses predictable /tmp path, persisted plaintext on failure |
| SEC-005 | Medium  | Config loading           | Config files sourced without ownership/permission validation                |
| SEC-006 | Medium  | Installer privileges     | Broad `chown *` with `|| true` masking during root install                 |
| SEC-007 | Medium  | Sudoers                  | `journalctl` sudoers rule has trailing `*` wildcard                        |
| SEC-008 | Low     | Process management       | `pkill -f` by path pattern can kill unintended processes                   |
| SEC-009 | Low     | Robustness               | `set -euo pipefail` absent; widespread `|| true` on security-relevant paths |
| SEC-010 | Low     | Logging                  | Log file redaction incomplete; `_oci_redact_cmd` covers only `--password`  |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** High: 2, Medium: 5, Low: 3
