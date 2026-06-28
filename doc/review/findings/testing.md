# Testing Findings - odb_datasafe v0.20.4

**Scope:** tests/ (all 32 BATS files), tests/run_tests.sh, Makefile test targets,
.github/workflows/ci.yml, lib/ssh_helpers.sh

---

## Findings

### TEST-001 - `make test` and `make test-all` swallow BATS failure exit codes

- **Severity:** Critical
- **Evidence:** `Makefile:127-129` (non-timeout branch) - `$(BATS) ... && echo "Tests passed" || echo "..."`.
  The `|| echo` replaces non-zero exit from BATS with zero. Timeout branch (`:117-126`) captures
  `rc=$$?` but has no `exit $$rc`. `make check` (`:141`) and `make ci` (`:347`) depend on
  `make test` - they also exit zero on test failures. `.github/workflows/ci.yml:65` additionally
  sets `continue-on-error: true`.
- **Impact:** Broken tests can never block a PR or release.
- **Recommendation:** Remove `|| echo` from non-timeout branch. Add `exit $$rc` after `fi` in
  timeout branch. Remove `continue-on-error: true` from CI workflow.

---

### TEST-002 - `find_connector_base()` has no test coverage

- **Severity:** Critical
- **Evidence:** `bin/install_datasafe_service.sh:282-299` (function added in commit `7082c9f`);
  `tests/install_datasafe_service.bats` - no test references `find_connector_base`.
- **Impact:** The auto-discovery function that fixed the most recent defect series has no
  regression coverage. Future regressions will not be caught before release.
- **Required tests:** (1) Connector under non-default base, `ORACLE_BASE` unset - assert
  installer finds it; (2) No candidate path contains connector - assert exit non-zero with
  "not found" message.

---

### TEST-003 - `install_service()` User= mismatch auto-regeneration has no regression test

- **Severity:** Critical
- **Evidence:** `bin/install_datasafe_service.sh:927-937` (commits `46a58ff` + `7082c9f`);
  no test in `tests/install_datasafe_service.bats` references `User=` mismatch.
- **Required test:** Prepare with `--user alice`, run `--install --user bob --dry-run`,
  assert output contains regeneration warning and service file reflects `User=bob`.

---

### TEST-004 - Missing sudoers warning path has no test

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:960-963` (commit `46a58ff`); no test
  triggers this warning branch.
- **Required test:** Run `--prepare`, delete generated sudoers file, run `--install --dry-run`,
  assert output contains "Sudoers file not found".

---

### TEST-005 - ExecStart binary validation path has no test

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:939-946` (commit `46a58ff`); no test sets
  `ORADBA_BASE` to a non-existent path.
- **Required test:** Prepare with `ORADBA_BASE=/nonexistent`, run `--install --dry-run`,
  assert output contains "ExecStart binary not found".

---

### TEST-006 - Log directory creation during install has no test

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:997-1003` (commit `7082c9f`); no test
  verifies `${CONNECTOR_HOME}/log` is created during install.
- **Required test:** Run `--install --dry-run` with connector home lacking `log/` subdirectory;
  assert output contains "Creating connector log directory".

---

### TEST-007 - `oci_exec` stderr isolation has no regression test

- **Severity:** High
- **Evidence:** Commit `c74c7ad` - "FutureWarning on stderr was concatenated with data returned
  to callers - breaking ds_target_list.sh -C -v". All mock `oci` implementations in
  `lib_oci_helpers.bats` write only to stdout.
- **Required test:** Mock `oci` emitting `FutureWarning:` to stderr plus valid JSON to stdout;
  assert `oci_exec` return value contains only JSON.

---

### TEST-008 - `ssh_helpers.sh` library is entirely untested

- **Severity:** High
- **Evidence:** `lib/ssh_helpers.sh` contains `ssh_require_tools`, `ssh_exec`, `ssh_scp_to`,
  `ssh_check` (lines 43-126). Grep for `ssh_helpers` across `tests/` returns zero matches.
  `ds_lib.sh:33` sources `ssh_helpers.sh` as a required module.
- **Recommendation:** Create `tests/lib_ssh_helpers.bats` covering all four functions,
  including tool-not-found, command failure, and stderr isolation scenarios.

---

### TEST-009 - Security-sensitive credential functions in `common.sh` are entirely untested

- **Severity:** High
- **Evidence:** `lib/common.sh` functions `decode_base64_file` (:577), `decode_base64_string`
  (:606), `is_base64_string` (:635), `normalize_secret_value` (:679), `find_password_file`
  (:700). Zero matches across all test files.
- **Required tests:** `is_base64_string` with valid/invalid/empty; `normalize_secret_value`
  with literal vs file-path input; `find_password_file` with existing file, non-existent, and
  `..` path.

---

### TEST-010 - DELETED-state target re-registration fix has no regression test

- **Severity:** High
- **Evidence:** Commit `da64082` - "registering a target whose display name matched an existing
  DELETED target was blocked". `tests/script_ds_target_register.bats` - no test mocks OCI
  returning a DELETED lifecycle-state target.
- **Required test:** Mock OCI returning `"lifecycle-state": "DELETED"` for target name; run
  `ds_target_register.sh --dry-run`; assert exit 0 (registration proceeds).

---

### TEST-011 - `ds_target_update_service.sh` PUT semantics (fetch before update) has no test

- **Severity:** High
- **Evidence:** Commit `00fba6d` - "fetch current database-details before update (PUT semantics)".
  `tests/script_ds_target_update_service.bats` has 4 tests, none verify call order.
- **Required test:** Record mock call order; assert `target-database get` appears before
  `target-database update`.

---

### TEST-012 - 12 test assertions accept both status 0 and status 1 as valid outcomes

- **Severity:** High
- **Evidence:** 12 occurrences of `[ "$status" -eq 0 ] || [ "$status" -eq 1 ]` in
  `lib_oci_helpers.bats` (8) and `uninstall_all_datasafe_services.bats` (3). These tests can
  never fail.
- **Impact:** Zero signal - functions could be broken and these tests would still pass.
- **Recommendation:** Fix mocks to return appropriate data (assert status 0), or use BATS
  `skip` with a clear reason. The `|| [ "$status" -eq 1 ]` pattern must be removed.

---

### TEST-013 - `ds_target_activate.sh` ERR trap on multi-target loop has no regression test

- **Severity:** Medium
- **Evidence:** Commit `fb7813d` - "guard loop against ERR trap on single-target failure".
  `tests/script_ds_target_activate.bats` (10 tests) - none exercise two-target partial failure.
- **Required test:** Mock OCI to fail on target-1 and succeed on target-2; assert script
  does not abort after target-1 failure; exit code indicates partial success.

---

### TEST-014 - Integration test files inconsistently excluded from `make test`

- **Severity:** Medium
- **Evidence:** `Makefile:117` - excludes only `integration_tests.bats`, not
  `integration_param_combinations.bats`. `integration_tests.bats` has `skip_if_no_oci_config`
  guards on some tests but not all.
- **Recommendation:** Either rename exclusion pattern to `integration*.bats` for consistency,
  or add `skip_if_no_oci_config` guards to every test in both integration files.

---

### TEST-015 - `lib_common.bats` teardown does not restore all exported variables

- **Severity:** Medium
- **Evidence:** `tests/lib_common.bats:63-66` - `teardown()` does not unset `DRY_RUN` or `ARGS`.
  `parse_common_opts` tests at `:191-228` set `DRY_RUN=true` which persists across tests.
- **Recommendation:** Add `DRY_RUN`, `ARGS`, `VERBOSE` and all variables set by `parse_common_opts`
  to the `teardown()` unset list.

---

### TEST-016 - Three `skip` tests in `edge_case_tests.bats` are permanently dead code

- **Severity:** Low
- **Evidence:** `tests/edge_case_tests.bats:153` (jq missing), `:209,213` (permission tests) -
  all permanently skipped. Count toward test total but test nothing.
- **Recommendation:** Implement the jq-missing test using PATH manipulation (same technique
  as oci mocking). Convert permission tests using `chmod` on temp directories. Remove rather
  than leaving as permanent skips.

---

## Required Regression Tests

<!-- markdownlint-disable MD013 -->
| ID     | Target | Scenario | Expected Assertion |
|--------|--------|----------|--------------------|
| REG-001 | `find_connector_base()` | Connector under non-default base; `ORACLE_BASE` unset | Exit 0; detected base in output |
| REG-002 | `find_connector_base()` | No candidate path contains connector | Exit non-zero; "not found" in output |
| REG-003 | `install_service()` User= mismatch | Prepared with `--user alice`; install with `--user bob` | Regeneration warning; `User=bob` in service file |
| REG-004 | `install_service()` missing sudoers | Prepared; sudoers deleted; `--install --dry-run` | "Sudoers file not found" in output |
| REG-005 | `install_service()` missing ExecStart | `ORADBA_BASE=/nonexistent`; `--install --dry-run` | "ExecStart binary not found" in output |
| REG-006 | Log directory creation | Connector home lacks `log/`; `--install --dry-run` | "Creating connector log directory" in output |
| REG-007 | `oci_exec` stderr isolation | Mock `oci` emits warning to stderr + JSON to stdout | `oci_exec` returns only JSON |
| REG-008 | DELETED target registration | Mock OCI returns DELETED lifecycle-state target | Registration proceeds; exit 0 |
| REG-009 | `ds_target_update_service.sh` PUT | Record call order; `--apply` mode | `target-database get` before `target-database update` |
| REG-010 | `ds_target_activate.sh` multi-target | Target-1 fails, target-2 succeeds | Script does not abort; partial-success exit code |
| REG-011 | `normalize_secret_value` | Input is file path to existing password file | Returns file contents |
| REG-012 | `normalize_secret_value` | Input is literal password string | Returns literal string unchanged |
<!-- markdownlint-enable MD013 -->

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID      | Severity | Area               | One-line                                                              |
|---------|----------|--------------------|-----------------------------------------------------------------------|
| TEST-001 | Critical | CI gate            | `make test` and `make test-all` swallow bats failure exit codes       |
| TEST-002 | Critical | Coverage           | `find_connector_base()` - no coverage for fix introduced in v0.20.4  |
| TEST-003 | Critical | Coverage           | User= mismatch auto-regeneration - no regression test                 |
| TEST-004 | High     | Coverage           | Missing sudoers warning path - no test                                |
| TEST-005 | High     | Coverage           | ExecStart binary validation - no test                                 |
| TEST-006 | High     | Coverage           | Log directory creation - no test                                      |
| TEST-007 | High     | Coverage           | `oci_exec` stderr isolation - no regression for the shipped defect    |
| TEST-008 | High     | Coverage           | `ssh_helpers.sh` entirely untested (364 LOC)                          |
| TEST-009 | High     | Coverage           | Credential decode/normalize functions entirely untested               |
| TEST-010 | High     | Coverage           | DELETED-state target fix (commit da64082) - no regression             |
| TEST-011 | High     | Coverage           | PUT semantics fix (commit 00fba6d) - no regression                    |
| TEST-012 | High     | Test quality       | 12 assertions accept status 0 or 1 - zero signal                      |
| TEST-013 | Medium   | Coverage           | ERR trap multi-target loop fix - no regression                        |
| TEST-014 | Medium   | Test infrastructure | Integration test exclusion inconsistent                               |
| TEST-015 | Medium   | Test isolation     | `lib_common.bats` teardown leaves state leaking                       |
| TEST-016 | Low      | Test quality       | 3 permanently skipped tests in edge_case_tests.bats                   |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** Critical: 3, High: 9, Medium: 3, Low: 1
