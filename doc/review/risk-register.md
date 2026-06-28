# Risk Register - odb_datasafe v0.20.4

Critical and High severity findings only. Risk Score = Likelihood x Impact on a
1-9 scale (Low=1, Med=2, High=3 per axis). Items scoring >= 7 are tagged
`[BLOCKER]` - they must be resolved before the v1.0.0 tag. Owner is a suggested
role, not a person.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Severity | Finding | Likelihood | Impact | Risk Score | Mitigation | Owner |
|----|----------|---------|-----------|--------|-----------|------------|-------|
| REL-001 (=TEST-001, REL-002) | Critical | `make test`/CI mask bats exit code - tests can never fail a PR or release | High | High | 9 [BLOCKER] | Remove `|| echo`; add `exit $$rc`; drop `continue-on-error: true` | Release Eng |
| ORA-001 (=SEC-001) | Critical | Hardcoded `DS_Admin.2025` admin password in committed SQL | High | High | 9 [BLOCKER] | Default to `''`, fail on empty `&2`; rotate deployed accounts; purge from history | Security |
| TEST-002 | Critical | `find_connector_base()` (the v0.20.4 fix) has no regression test | High | High | 9 [BLOCKER] | Add REG-001/REG-002 before any installer change | Test/QA |
| TEST-003 | Critical | User= mismatch auto-regeneration has no regression test | High | High | 9 [BLOCKER] | Add REG-003 (prepare alice / install bob) | Test/QA |
| ARCH-007 (=DEP-002, DEP-007) | High | Hardcoded Oracle/systemd paths - active source of v0.20.2-v0.20.4 defects | High | High | 9 [BLOCKER] | Centralize layout discovery; resolve binaries via `command -v`; validate in `--prepare` | Architecture |
| REL-007 | High | `make release` bumps version without lint/test gate | High | High | 9 [BLOCKER] | `release: check version-bump-patch tag` | Release Eng |
| REL-006 | High | Same-day patch cadence - no pre-release validation gate | High | High | 9 [BLOCKER] | Require `make check` precondition; installer pre-release checklist | Release Eng |
| SEC-002 (=ORA-002) | High | DB secret on command line, visible via `ps`/history | High | High | 9 [BLOCKER] | Warn on `-P`; steer to `--secret-file`/`read -rs`/`file://` | Security |
| SEC-004 (=BASH-015) | Medium->High risk | Register payload at predictable /tmp path, plaintext secret, no EXIT trap, preserved on failure | High | High | 9 [BLOCKER] | `mktemp` + `umask 077` + EXIT trap; mask password on failure persist | Security |
| DEP-001 (=DEP-011, BASH-021) | High | No bash 4.0+ guard; silent breakage on bash 3.2 (macOS) | High | Med | 6 | Add `BASH_VERSINFO` guard in `lib/common.sh`; document requirement | Robustness |
| ORA-013 | High | `manage data-safe-family in tenancy` over-broad IAM grant | Med | High | 6 | Constrain with `where target.compartment.id=` per existing JSON example | Security |
| ORA-003 | High | `PASSWORD_LOCK_TIME` ~5 min vs CIS 1 day - brute-force lockout neutered | Med | High | 6 | Set `PASSWORD_LOCK_TIME 1`, finite `INACTIVE_ACCOUNT_TIME` | Security |
| TEST-007 (=ARCH-005, BASH-014, SEC-010) | High | `oci_exec` stderr isolation - shipped `2>&1` defect has no regression | High | Med | 6 | Route `ds_refresh_target` via `oci_exec`; add REG-007 | Test/QA |
| ARCH-001 (=BASH-016, BASH-006) | High | Installer 1372-LOC god script; no ERR/EXIT trap, parallel framework | High | Med | 6 | See DECISION D-1; add traps + tests now, refactor scope TBD | Architecture |
| BASH-001 (=ARCH-009, BASH-003) | High | `setup_error_handling` deferred; bootstrap runs unprotected | Med | High | 6 | Enable strict mode + ERR trap in shared bootstrap | Robustness |
| BASH-002 (=SEC-009) | High | 2 scripts have zero error protection; OCI failures return 0 | High | Med | 6 | Add `set -euo pipefail` + `setup_error_handling` | Robustness |
| PERF-001 | Critical | Default-on per-target OCI GET enrichment, O(N) serial (20-80s for 10 targets) | High | Med | 6 | Default `ENRICH_MISSING=false`; opt-in `--enrich` or parallelize | Performance |
| REL-010 | High | No documented v1.0.0 readiness gate | High | Med | 6 | Create `doc/milestone-v1.0.0.md` with pass/fail criteria | Release Eng |
| REL-003 | High | shfmt format-check absent from CI | Med | Med | 4 | Add `make format-check` as hard CI gate | Release Eng |
| TEST-008 | High | `ssh_helpers.sh` (364 LOC) entirely untested | Med | Med | 4 | Create `tests/lib_ssh_helpers.bats` | Test/QA |
| TEST-009 | High | Credential decode/normalize functions untested | Med | High | 6 | Add tests for is_base64/normalize_secret/find_password_file | Test/QA |
| TEST-012 | High | 12 assertions accept status 0 or 1 - zero signal | High | Med | 6 | Fix mocks to assert real status; remove `|| [ "$status" -eq 1 ]` | Test/QA |
| TEST-004 | High | Missing sudoers warning path - no test | Med | Med | 4 | Add REG-004 | Test/QA |
| TEST-005 | High | ExecStart binary validation - no test | Med | Med | 4 | Add REG-005 | Test/QA |
| TEST-006 | High | Log directory creation - no test | Med | Med | 4 | Add REG-006 | Test/QA |
| TEST-010 | High | DELETED-state target fix - no regression | Med | Med | 4 | Add REG-008 | Test/QA |
| TEST-011 | High | PUT-semantics fix - no regression | Med | Med | 4 | Add REG-009 | Test/QA |
| REL-004 | High | Script header versions frozen at v0.19.1 | High | Low | 3 | Update headers on release bump via Makefile | Release Eng |
| DOC-001 | High | README/index "Latest Release" stale (v0.19.1) | High | Low | 3 | Update to v0.20.4; derive from VERSION | Docs |
| DOC-002 | High | README test counts contradictory (127/227/287) | Med | Low | 2 | Align to single authoritative count | Docs |
| DOC-005 | High | `--remove` documented but command is `--uninstall` | High | Med | 6 | s/`--remove`/`--uninstall`/ in two docs | Docs |
| DOC-009 | High | `etc/.env.example` referenced; file does not exist | High | Med | 6 | Point to `etc/datasafe.conf.example`; verify loader | Docs |
| PERF-002 | High | `ds_resolve_target_name` extra OCI GET per target (100-400s for 50) | Med | Med | 4 | Accept optional `target_name`; GET only when empty | Performance |
| PERF-003 | High | `oci_resolve_compartment_ocid` 3x without caching | High | Med | 6 | Add `_COMP_OCID_BY_NAME_CACHE` | Performance |
| PERF-005 | High | 8+ `echo|jq` subshells per connector in summary display | High | Low | 3 | Single-pass jq `@tsv` -> `while read` | Performance |
<!-- markdownlint-enable MD013 MD060 -->

## Blocker summary

The following score >= 7 and block the v1.0.0 tag:

- REL-001 - no working CI/test gate (also covers TEST-001, REL-002)
- ORA-001 - hardcoded admin password (also covers SEC-001)
- TEST-002 - `find_connector_base()` untested
- TEST-003 - User= regeneration untested
- ARCH-007 - hardcoded layout paths (the recurring defect engine)
- REL-007 - release without lint/test gate
- REL-006 - no pre-release validation cadence
- SEC-002 - secret visible in process list
- SEC-004 - predictable plaintext credential temp file

Recommended sequencing: clear the CI/release gate (REL-001, REL-002, REL-007,
REL-006) first so subsequent fixes are actually verified, then the credential
blockers (ORA-001, SEC-002, SEC-004), then the installer regression tests
(TEST-002, TEST-003) ahead of the ARCH-007 layout-discovery work.

## Notes on likelihood and impact

- Likelihood "High" reflects defects that trigger on normal operation or are
  already in the public repo (hardcoded password, stale CI gate), not theoretical.
- Impact "High" reflects credential exposure, infrastructure misconfiguration, or
  the inability to detect regressions before release.
- SEC-004 is reported Medium severity by the security domain but carries High
  practical risk (plaintext secret on disk, predictable path, preserved on
  failure); it is scored 9 here and treated as a blocker.
