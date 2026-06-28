# Dependency Findings - odb_datasafe v0.20.4

**Scope:** lib/common.sh (require_cmd), lib/oci_helpers.sh, bin/install_datasafe_service.sh,
.github/workflows/, Makefile, README.md

---

## Findings

### DEP-001 - No runtime bash version guard; bash 4.0+ features used throughout

- **Severity:** High
- **Evidence:** `mapfile` used in 12 locations: `bin/install_datasafe_service.sh:315,482`,
  `bin/ds_target_delete.sh:280`, `bin/ds_target_connector_summary.sh:701,734,767`,
  `bin/ds_target_refresh.sh:359`, `bin/ds_target_activate.sh:508`,
  `bin/odb_datasafe_help.sh:290,386`, `bin/uninstall_all_datasafe_services.sh:297,356`.
  `declare -A` used in `bin/ds_target_details.sh:51`, `bin/ds_target_export.sh:67`.
  `${var^^}` in `lib/common.sh:108-116`, `bin/ds_database_prereqs.sh:46,66`,
  `bin/ds_target_audit_trail.sh:296,383`. No `BASH_VERSINFO` check anywhere.
  macOS ships bash 3.2. README.md:140 documents "Bash 4.0+" but no runtime enforcement.
- **Recommendation:** Add version guard to `lib/common.sh` at source time:
  ```bash
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
      echo "ERROR: bash 4.0+ required (found ${BASH_VERSION})" >&2; exit 1
  fi
  ```

---

### DEP-002 - `systemctl`, `visudo`, and `getent` invoked without existence checks

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:332` - `systemctl list-unit-files` called
  unconditionally; `:994,1027,1031,1035,1047` - `systemctl stop/daemon-reload/enable/start/status`;
  `:1017` - `visudo -c -f` (not present on macOS); `:424` - `getent group` (macOS uses `dscl`).
  `bin/uninstall_all_datasafe_services.sh` - multiple `systemctl` calls without check.
  None guarded by `command -v` or `require_cmd`.
- **Recommendation:** Add pre-flight `require_cmd systemctl visudo` block at top of
  `install_service()` and `list_connectors()`. Document macOS as unsupported platform for the
  install script, or add explicit OS detection (`uname -s`) with clear error.

---

### DEP-003 - `grep -oP` (PCRE) used - incompatible with BSD grep on macOS

- **Severity:** Medium
- **Evidence:** `bin/ds_connector_update.sh:804`:
  `version=$(... | grep -oP '(?<=version : )[0-9.]+' | head -1)`. The `-P` flag is not
  supported by BSD grep. Project rules (`shell-scripts.md`) explicitly prohibit `grep -P`.
  Fails silently on macOS, returning empty version string.
- **Recommendation:** Replace with:
  `version=$(... | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)`

---

### DEP-004 - `python3` invoked to run vendor `setup.py` without version check or integrity verification

- **Severity:** Medium
- **Evidence:** `bin/ds_connector_create.sh:484` - `python3 - "$setup_py"`;
  `bin/ds_connector_update.sh:749,742` - `BUNDLE_KEY_INPUT="$BUNDLE_KEY" python3 - "$setup_py"`.
  `python3` existence is checked via `require_cmd python3` but no minimum Python version
  verified. `setup.py` is vendor code from OCI connector bundle, executed without hash
  verification.
- **Recommendation:** Add Python version guard:
  `python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" || die "Python 3.8+ required"`.
  Verify bundle checksum before unpacking and executing.

---

### DEP-005 - `ds_target_move.sh` makes OCI API calls without `require_oci_cli()` validation

- **Severity:** Medium
- **Evidence:** `bin/ds_target_move.sh` - 8 OCI calls (lines 325, 469, 496, 514, 542, 560,
  588, 606) without calling `require_oci_cli()`. All other OCI-using scripts call this
  pre-flight check.
- **Recommendation:** Add `require_oci_cli` in `main()` of `ds_target_move.sh` before first
  OCI-dependent call.

---

### DEP-006 - `sqlplus` requires `ORACLE_HOME` on PATH but only `ORACLE_SID` is validated

- **Severity:** Medium
- **Evidence:** `bin/ds_database_prereqs.sh:854-856` - `require_cmd sqlplus mktemp base64`,
  `require_var ORACLE_SID`. `ORACLE_HOME` is referenced in error messages (`:1060, :1082`)
  but not validated. Script uses `/ as sysdba` OS auth which requires the user to be in
  the `dba` OS group - not checked.
- **Recommendation:** Add:
  ```bash
  require_var ORACLE_SID ORACLE_HOME
  [[ -d "$ORACLE_HOME" ]] || die "ORACLE_HOME directory not found: $ORACLE_HOME"
  ```

---

### DEP-007 - `oradba_dsctl.sh` absence generates broken systemd unit without fatal error

- **Severity:** Medium
- **Evidence:** `bin/install_datasafe_service.sh:939-945` - ExecStart binary validation emits
  WARNING but does not abort installation. Allows installing a service unit with a non-executable
  `ExecStart` path, which fails silently at boot.
- **Recommendation:** Promote to fatal when `REGISTRY_ALIAS` is set (i.e. using oradba mode):
  `if [[ -n "${REGISTRY_ALIAS:-}" ]] && [[ ! -x "${exec_bin}" ]]; then die "..."; fi`

---

### DEP-008 - No OCI CLI minimum version enforced

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:172-180` (`require_oci_cli()`) checks existence and auth only.
  Uses `oci data-safe` subcommands requiring OCI CLI 3.x; no version floor checked.
  `doc/release_notes/v0.20.1.md:6` references oci-cli 3.83.x.
- **Recommendation:** Add minimum version check in `require_oci_cli()`. Document minimum
  supported OCI CLI version in README prerequisites.

---

### DEP-009 - `.extension: uses_oradba_libs: false` is accurate but `oradba_dsctl.sh` and `oradba_homes.sh` are undocumented runtime dependencies

- **Severity:** Low
- **Evidence:** `.extension:7` - `uses_oradba_libs: false`. But `bin/install_datasafe_service.sh:570`,
  `bin/uninstall_all_datasafe_services.sh:215`, `bin/ds_connector_create.sh:609-617` all call
  external OraDBA tools. Not mentioned in README prerequisites.
- **Recommendation:** Add to README prerequisites: "Optional: oradba_dsctl.sh and oradba_homes.sh
  from the OraDBA base installation for OraDBA-managed deployments."

---

### DEP-010 - `date +%s` assumed portable but undocumented dependency

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:1140,1282`, `bin/ds_database_prereqs.sh:992`. Not POSIX
  standardized but supported on macOS since 10.6 and all Linux distributions.
- **Recommendation:** No change required for v1.0.0. Document as implicit dependency if strict
  POSIX adherence is ever required.

---

### DEP-011 - `mapfile` (bash 4.0) used in 12 locations with no fallback for bash 3.x

- **Severity:** High
- **Evidence:** See DEP-001 for locations. No fallback `while IFS= read -r` pattern exists.
  `bash42_compatibility.bats` validates bash 4.2 compatibility but does not guard against 3.2.
- **Recommendation:** Consolidated with DEP-001: runtime bash version guard at entry resolves
  both. Individual `mapfile` calls do not need refactoring once the version guard exists.

---

### DEP-012 - Vendor `setup.py` from OCI connector bundle executed without hash verification

- **Severity:** Medium
- **Evidence:** `bin/ds_connector_create.sh:484`, `bin/ds_connector_update.sh:749`. Bundle
  fetched via authenticated OCI API call but not hash-verified before extraction. Bundle
  stored locally and re-used without re-validation.
- **Recommendation:** Verify bundle checksum (from OCI API) before unpacking. At minimum,
  document in operational guide that bundle integrity is not independently verified.

---

### DEP-013 - `ds_database_prereqs.sh` duplicates logging infrastructure instead of sourcing `lib/common.sh`

- **Severity:** Low
- **Evidence:** `bin/ds_database_prereqs.sh:35-130` reimplements `_log_level_num()`, `log()`,
  and all log wrappers. Uses `${1^^}` (bash 4.0) at `:46,66,151` without version guard.
  `lib/common.sh` provides identical functions.
- **Recommendation:** Replace duplicated logging block with `source "${SCRIPT_DIR}/../lib/common.sh"`.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID     | Severity | Area                | One-line                                                              |
|--------|----------|---------------------|-----------------------------------------------------------------------|
| DEP-001 | High    | Bash version        | No bash 4.0+ runtime guard; macOS ships bash 3.2                      |
| DEP-002 | High    | OS commands         | `systemctl`, `visudo`, `getent` invoked without existence checks      |
| DEP-011 | High    | Bash version        | `mapfile` in 12 locations with no bash 3.x fallback (same as DEP-001) |
| DEP-003 | Medium  | BSD compat          | `grep -oP` (PCRE) used; incompatible with BSD grep on macOS           |
| DEP-004 | Medium  | Python / supply-chain | `python3` runs vendor `setup.py` without version check or hash verify |
| DEP-005 | Medium  | OCI pre-flight      | `ds_target_move.sh` missing `require_oci_cli()` pre-flight check       |
| DEP-006 | Medium  | Oracle prereqs      | `sqlplus` requires `ORACLE_HOME` but only `ORACLE_SID` is validated   |
| DEP-007 | Medium  | oradba dependency   | `oradba_dsctl.sh` absence generates broken service unit (non-fatal)   |
| DEP-012 | Medium  | Supply-chain        | Vendor `setup.py` executed without checksum verification              |
| DEP-008 | Low     | OCI CLI version     | No minimum OCI CLI version enforced                                   |
| DEP-009 | Low     | oradba dependencies | `oradba_dsctl.sh` / `oradba_homes.sh` undocumented runtime deps       |
| DEP-010 | Low     | Portability         | `date +%s` undocumented POSIX extension dependency                    |
| DEP-013 | Low     | Duplication         | `ds_database_prereqs.sh` duplicates logging from lib/common.sh        |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** High: 3 (DEP-001 and DEP-011 share root cause), Medium: 6, Low: 4
