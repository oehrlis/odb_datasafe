# Technical Debt Register - odb_datasafe v0.20.4

One row per finding across all 9 domains. Cross-domain duplicates are listed under
their canonical ID with the folded ID noted; they are counted once in the effort
total. Effort: S = 0.5d, M = 1d, L = 2d, XL = 5d. Debt types: Robustness, Security,
Architecture, Documentation, Testing, Performance, Compliance.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Severity | Domain | Title | Debt Type | Effort | Milestone |
|----|----------|--------|-------|-----------|--------|-----------|
| ORA-001 (=SEC-001) | Critical | Oracle | Hardcoded default password `DS_Admin.2025` in SQL | Security | S | M1 |
| REL-001 (=TEST-001, REL-002) | Critical | Release | `make test`/CI mask bats exit code | Testing | S | M1 |
| PERF-001 | Critical | Performance | Default-on per-target OCI GET enrichment, O(N) | Performance | S | M4 |
| TEST-002 | Critical | Testing | `find_connector_base()` has no coverage | Testing | M | M1 |
| TEST-003 | Critical | Testing | User= mismatch auto-regeneration no regression test | Testing | M | M1 |
| ARCH-001 (=BASH-016, BASH-006) | High | Architecture | Installer 1372-LOC god script bypasses framework | Architecture | XL | M3 |
| ARCH-002 (=PERF-008) | High | Architecture | Bootstrap boilerplate duplicated across 25 scripts | Architecture | M | M3 |
| ARCH-007 (=DEP-002, DEP-007) | High | Architecture | Hardcoded Oracle/systemd paths - defect root cause | Architecture | L | M3 |
| SEC-002 (=ORA-002) | High | Security | DB secret on command line, visible in `ps` | Security | S | M2 |
| ORA-003 | High | Oracle | `PASSWORD_LOCK_TIME` 5 min vs CIS 1 day | Compliance | S | M2 |
| ORA-013 | High | Oracle | `manage data-safe-family in tenancy` over-broad | Compliance | S | M2 |
| REL-003 | High | Release | shfmt format-check absent from CI | Testing | S | M1 |
| REL-004 | High | Release | Script header versions frozen at v0.19.1 | Documentation | S | M5 |
| REL-006 | High | Release | Same-day patch cadence - no pre-release gate | Testing | M | M1 |
| REL-007 | High | Release | `make release` runs without lint/test gate | Testing | S | M1 |
| REL-010 | High | Release | No documented v1.0.0 readiness checklist | Documentation | M | M1 |
| TEST-004 | High | Testing | Missing sudoers warning path - no test | Testing | S | M1 |
| TEST-005 | High | Testing | ExecStart binary validation - no test | Testing | S | M1 |
| TEST-006 | High | Testing | Log directory creation - no test | Testing | S | M1 |
| TEST-007 (=ARCH-005, BASH-014, SEC-010) | High | Testing | `oci_exec` stderr isolation - no regression | Testing | M | M1 |
| TEST-008 | High | Testing | `ssh_helpers.sh` entirely untested (364 LOC) | Testing | M | M4 |
| TEST-009 | High | Testing | Credential decode/normalize functions untested | Testing | M | M4 |
| TEST-010 | High | Testing | DELETED-state target fix - no regression | Testing | S | M4 |
| TEST-011 | High | Testing | PUT-semantics fix - no regression | Testing | S | M4 |
| TEST-012 | High | Testing | 12 assertions accept status 0 or 1 - zero signal | Testing | M | M4 |
| BASH-001 (=ARCH-009, BASH-003) | High | Bash | `setup_error_handling` deferred; bootstrap unprotected | Robustness | M | M4 |
| BASH-002 (=SEC-009) | High | Bash | 2 scripts have no error protection at all | Robustness | S | M1 |
| DEP-001 (=DEP-011, BASH-021) | High | Deps | No bash 4.0+ runtime guard; macOS ships 3.2 | Robustness | S | M1 |
| DOC-001 | High | Docs | README/index latest release stale (v0.19.1) | Documentation | S | M5 |
| DOC-002 | High | Docs | README test counts contradictory (127/227/287) | Documentation | S | M5 |
| DOC-005 | High | Docs | `--remove` documented but does not exist | Documentation | S | M5 |
| DOC-009 | High | Docs | `etc/.env.example` referenced; file does not exist | Documentation | S | M5 |
| PERF-002 | High | Performance | `ds_resolve_target_name` extra OCI GET per target | Performance | M | M4 |
| PERF-003 | High | Performance | `oci_resolve_compartment_ocid` 3x, no cache | Performance | S | M4 |
| PERF-005 | High | Performance | 8+ `echo|jq` subshells per connector in summary | Performance | M | M5 |
| ARCH-003 (=BASH-020) | Medium | Architecture | `is_ocid` defined twice, silent shadowing | Architecture | S | M5 |
| ARCH-005 | Medium | Architecture | `ds_refresh_target` bypasses `oci_exec` wrapper | Architecture | M | M4 |
| ARCH-006 | Medium | Architecture | Config naming: loader vs shipped example mismatch | Architecture | S | M5 |
| ARCH-008 | Medium | Architecture | `--install` mutates `--prepare` artifacts (leaky) | Architecture | M | M3 |
| ARCH-009 | Medium | Architecture | ERR trap opt-in/dormant (folded into BASH-001) | Robustness | S | M4 |
| SEC-003 | Medium | Security | Bundle password on OCI CLI argv | Security | S | M2 |
| SEC-004 (=BASH-015) | Medium | Security | Register payload predictable /tmp, plaintext, no trap | Security | S | M2 |
| SEC-005 | Medium | Security | Config files sourced without ownership checks | Security | M | M2 |
| SEC-006 (=BASH-023) | Medium | Security | Broad `chown *` with `|| true` during root install | Security | S | M2 |
| SEC-007 | Medium | Security | `journalctl` sudoers rule trailing `*` wildcard | Security | S | M2 |
| ORA-004 | Medium | Oracle | Profile created without explicit `CONTAINER` scope | Compliance | S | M2 |
| ORA-005 | Medium | Oracle | `GRANT RESOURCE` over-broad for service account | Compliance | S | M2 |
| ORA-006 | Medium | Oracle | `--grant-mode ALL` activates ANY-priv grants | Compliance | S | M2 |
| ORA-007 | Medium | Oracle | `DS_GRANT_MODE=ALL` default over-provisions | Compliance | S | M2 |
| ORA-009 | Medium | Oracle | HOST + predictable /tmp in extension_comprehensive.sql | Security | S | M2 |
| ORA-014 | Medium | Oracle | Service account has `use keys` + tenancy reads | Compliance | S | M2 |
| REL-005 | Medium | Release | Installer `SCRIPT_VERSION=v1.1.0` out of sync | Documentation | S | M5 |
| TEST-013 | Medium | Testing | ERR-trap multi-target loop fix - no regression | Testing | S | M4 |
| TEST-014 | Medium | Testing | Integration test exclusion inconsistent | Testing | S | M4 |
| TEST-015 | Medium | Testing | `lib_common.bats` teardown leaks state | Testing | S | M4 |
| BASH-004 | Medium | Bash | Bare `((count++))` under `set -e` (fragile) | Robustness | S | M4 |
| BASH-007 | Medium | Bash | OCI `--query` embeds unsanitized compartment name | Security | S | M4 |
| BASH-008 | Medium | Bash | jq filter embeds shell vars (2 in ds_target_register) | Security | S | M4 |
| BASH-013 | Medium | Bash | `generate_bundle_key` unbounded loop | Robustness | S | M4 |
| BASH-014 | Medium | Bash | `ds_refresh_target` `2>&1` bypass (folded TEST-007) | Robustness | M | M4 |
| BASH-016 | Medium | Bash | Installer no ERR/EXIT trap (folded ARCH-001) | Robustness | S | M3 |
| ARCH-011 (=BASH-019) | Medium | Architecture | `resolve_*_to_vars` uses eval | Security | S | M4 |
| BASH-023 | Medium | Bash | Auto-regen mid-install, chown failure masked (=SEC-006) | Security | S | M3 |
| DEP-003 | Medium | Deps | `grep -oP` (PCRE) breaks on BSD grep | Robustness | S | M5 |
| DEP-004 | Medium | Deps | `python3` runs vendor `setup.py`, no version check | Security | S | M2 |
| DEP-005 | Medium | Deps | `ds_target_move.sh` missing `require_oci_cli()` | Robustness | S | M4 |
| DEP-006 | Medium | Deps | `sqlplus` needs `ORACLE_HOME`, not validated | Robustness | S | M4 |
| DEP-007 | Medium | Deps | Missing `oradba_dsctl.sh` -> broken unit (non-fatal) | Robustness | S | M3 |
| DEP-012 (=DEP-004) | Medium | Deps | Vendor `setup.py` no checksum verification | Security | M | M2 |
| DOC-003 | Medium | Docs | Script count "16+" vs actual 30 | Documentation | S | M5 |
| DOC-004 | Medium | Docs | Script header version frozen; installer split identity | Documentation | S | M5 |
| DOC-006 | Medium | Docs | Options table omits prepare/install/uninstall | Documentation | S | M5 |
| DOC-007 | Medium | Docs | CONNECTOR_BASE auto-discovery not documented | Documentation | S | M5 |
| DOC-008 | Medium | Docs | Broken link to `v0.19.0.md` | Documentation | S | M5 |
| DOC-010 | Medium | Docs | lib/README.md v4.0.0 framing, wrong LOC, no ssh_helpers | Documentation | S | M5 |
| DOC-013 | Medium | Docs | CHANGELOG missing v0.19.2-v0.19.4 | Documentation | S | M5 |
| DOC-016 | Medium | Docs | No onboarding docs for `ds_connector_create.sh` | Documentation | M | M5 |
| PERF-004 | Medium | Performance | `ds_is_cdb_root_target` slow path per-target GET | Performance | M | M4 |
| PERF-006 | Medium | Performance | 3 `echo|jq` subshells per connector in detailed table | Performance | S | M5 |
| PERF-009 | Medium | Performance | 2 subshells per `log*` call even when filtered | Performance | S | M5 |
| PERF-012 | Medium | Performance | Bulk ops strictly serial, no bounded parallelism | Performance | L | M5 |
| ARCH-004 (=PERF-010) | Low | Architecture | Two identical mtime helpers in same file | Architecture | S | M5 |
| ARCH-010 | Low | Architecture | Version metadata drift across headers/literals | Documentation | S | M5 |
| ARCH-012 | Low | Architecture | `ssh_helpers.sh` loaded for all, used by few | Architecture | S | M5 |
| ARCH-013 | Low | Architecture | `oci_helpers.sh` owns Data Safe domain logic | Architecture | L | M5 |
| SEC-008 | Low | Security | `pkill -f` by path can kill unintended processes | Security | S | M2 |
| SEC-009 | Low | Security | `set -euo pipefail` absent; `|| true` masking | Robustness | M | M4 |
| SEC-010 | Low | Security | Log redaction incomplete (folded TEST-007) | Security | S | M4 |
| ORA-008 | Low | Oracle | No unpaired AUDIT/NOAUDIT (positive, no action) | Compliance | S | M5 |
| ORA-010 | Low | Oracle | v$database/v$instance cartesian join in templates | Robustness | S | M5 |
| ORA-011 | Low | Oracle | Vendor WHENEVER SQLERROR without FAILURE | Robustness | S | M5 |
| ORA-012 | Low | Oracle | Silent password-unchanged on ORA-28007 (documented) | Documentation | S | M5 |
| ORA-015 | Low | Oracle | `--ds-user`/`--pdb` not whitelisted before SQL | Security | S | M4 |
| ORA-016 | Low | Oracle | Vendor script unmodified, correct (positive) | Compliance | S | M5 |
| REL-008 | Low | Release | Release workflow runs tests twice | Performance | S | M5 |
| REL-009 | Low | Release | Tarball timestamp breaks reproducibility | Architecture | S | M5 |
| REL-011 | Low | Release | Missing git tags v0.19.2/v0.19.3 (historical) | Documentation | S | M5 |
| REL-012 | Low | Release | `[Unreleased]` CHANGELOG always empty | Documentation | S | M5 |
| TEST-016 | Low | Testing | 3 permanently skipped tests in edge_case_tests.bats | Testing | S | M5 |
| BASH-005 | Low | Bash | `((frame++))` in stacktrace - context-dependent | Robustness | S | M5 |
| BASH-006 | Low | Bash | Installer non-ERROR messages to stdout (folded ARCH-001) | Robustness | S | M3 |
| BASH-009 | Low | Bash | `echo|tr/jq/cut` subshell patterns in library | Performance | S | M5 |
| BASH-018 | Low | Bash | No `LC_ALL=C` on `tr` normalization | Robustness | S | M5 |
| BASH-020 | Low | Bash | `is_ocid` double-defined (folded ARCH-003) | Architecture | S | M5 |
| BASH-024 | Low | Bash | Empty array unsafe under `set -u` on bash 4.3- | Robustness | S | M4 |
| DEP-008 | Low | Deps | No minimum OCI CLI version enforced | Robustness | S | M5 |
| DEP-009 | Low | Deps | oradba tools undocumented runtime deps | Documentation | S | M5 |
| DEP-010 | Low | Deps | `date +%s` undocumented POSIX-extension dependency | Documentation | S | M5 |
| DEP-013 | Low | Deps | `ds_database_prereqs.sh` duplicates logging | Architecture | M | M5 |
| DOC-011 | Low | Docs | doc/testing.md version 0.7.1, conflicting counts | Documentation | S | M5 |
| DOC-012 | Low | Docs | tests/README.md version 0.9.0, incomplete table | Documentation | S | M5 |
| DOC-014 | Low | Docs | "new in v0.6.1" anachronistic annotation | Documentation | S | M5 |
| DOC-015 | Low | Docs | Install example 1 implies single-step install | Documentation | S | M5 |
| PERF-007 | Low | Performance | `sort|uniq-c|sort` on in-memory data | Performance | S | M5 |
| PERF-011 | Low | Performance | `echo|tr|tr` for string normalization | Performance | S | M5 |
<!-- markdownlint-enable MD013 MD060 -->

## Effort totals

Counting each canonical finding once (folded duplicate IDs not re-counted).

<!-- markdownlint-disable MD013 MD060 -->
| Effort | Count | Days each | Subtotal (days) |
|--------|-------|-----------|-----------------|
| S | 79 | 0.5 | 39.5 |
| M | 22 | 1.0 | 22.0 |
| L | 5 | 2.0 | 10.0 |
| XL | 1 | 5.0 | 5.0 |
| Total canonical findings | 107 | - | 76.5 |
<!-- markdownlint-enable MD013 MD060 -->

Estimated total remediation effort: approximately 76.5 engineer-days (~15-16
working weeks for a single engineer, less with parallelization across milestones).
M1 release-gate blockers account for roughly 7 days and should be cleared first.
