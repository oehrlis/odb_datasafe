# odb_datasafe v0.20.4 → v1.0.0 Roadmap Execution

## M1 — Release Gate Restoration (tag: v0.21.0)

**Goal:** Restore a working CI/release quality gate.

### Tasks

- [x] Read roadmap.md and relevant findings files
- [x] Fix Makefile: propagate BATS exit code (REL-001/TEST-001)
- [x] Fix Makefile: add format-check to check/ci chain (REL-003)
- [x] Fix Makefile: add check prerequisite to release target (REL-007)
- [x] Fix Makefile: add tasks/ and doc/review/ to markdownlint ignore (pre-existing lint issues)
- [x] Fix .github/workflows/ci.yml: remove continue-on-error: true (REL-002)
- [x] Fix .github/workflows/ci.yml: add format-check step
- [x] Fix sql/create_ds_admin_user.sql: remove DS_Admin.2025 default (ORA-001/C-1)
- [x] Fix lib/common.sh: add bash 4.0+ version guard (DEP-001/D-2)
- [x] Fix bin/ds_connector_register_oradba.sh: add set -euo pipefail + setup_error_handling (BASH-002)
- [x] Fix bin/ds_connector_update.sh: add set -euo pipefail + setup_error_handling (BASH-002)
- [x] Fix bin/install_datasafe_service.sh + uninstall_all_datasafe_services.sh: shfmt formatting
- [x] Update README.md: Latest Release to v0.20.4 (DOC-001)
- [x] Update doc/index.md: Latest Release to v0.20.4 (DOC-001)
- [x] Create doc/milestone-v1.0.0.md (REL-010)
- [x] Create doc/release_notes/v0.21.0.md
- [x] Update CHANGELOG.md with 0.21.0 entry
- [x] Bump VERSION to 0.21.0
- [-] Verify acceptance criteria (GATE 1) — make ci running
- [ ] GATE 1: present diff for human approval
- [ ] Commit + tag v0.21.0 (after approval)

### Acceptance Criteria

- [ ] Planted failing test causes make test to exit non-zero
- [ ] grep -c "continue-on-error" .github/workflows/ci.yml == 0
- [ ] make release aborts when make check fails
- [ ] grep -R "DS_Admin.2025" . == 0 matches
- [ ] bash 4.0+ guard active in lib/common.sh
- [ ] ds_connector_register_oradba.sh and ds_connector_update.sh have set -euo pipefail
- [ ] doc/milestone-v1.0.0.md exists

---

## M2 — Security Hardening (tag: v0.22.0) ✓ DONE

- [x] Read M2 findings (security.md, oracle.md, deps.md)
- [x] SEC-002: argv warning for -P/--ds-secret in ds_target_register.sh
- [x] SEC-003: bundle password via file:// in oci_helpers.sh:ds_generate_connector_bundle
- [x] SEC-004: mktemp + umask 077 + EXIT trap for register payload (ds_target_register.sh)
- [x] SEC-005: ownership/permission check in common.sh:load_config
- [x] SEC-006: remove || true from chown calls in install_datasafe_service.sh
- [x] SEC-007: remove trailing * from journalctl sudoers rule
- [x] SEC-008: constrain pkill -f in uninstall_all_datasafe_services.sh
- [x] ORA-003: PASSWORD_LOCK_TIME 1 + INACTIVE_ACCOUNT_TIME 35 in create_ds_admin_prerequisites.sql
- [x] ORA-004: CONTAINER=ALL for profile creation
- [x] ORA-005: replace GRANT RESOURCE with CREATE SESSION in create_ds_admin_user.sql
- [x] ORA-009: remove HOST + predictable /tmp in extension_comprehensive.sql
- [x] ORA-013/ORA-014: constrain IAM policies in doc/oci-iam-policies.md
- [x] DEP-004/DEP-012: Python 3.8+ check + checksum in ds_connector_create/update.sh
- [x] D-3: document --grant-mode ALL privilege surface in doc/database_prereqs.md
- [x] CHANGELOG + release notes v0.22.0
- [x] make ci passes → commit 35b9767 + tag v0.22.0

## M3 — Installer Hardening (tag: v0.23.0) ✓ DONE

- [x] Write REG-001..REG-006 regression tests (all 6 green after M3)
- [x] BASH-016: ERR + EXIT traps added to installer
- [x] BASH-006: all print_message levels routed to stderr
- [x] ARCH-007 (partial): systemctl/journalctl resolved via command -v
- [x] ARCH-008: --install auto-regen chown skipped in DRY_RUN mode
- [x] DEP-007: missing oradba_dsctl.sh aborts --prepare with clear error
- [x] Log dir creation reported in dry-run plan section
- [x] CHANGELOG + release notes v0.23.0
- [x] make ci passes → commit aa3a570 + tag v0.23.0

## M4 — Test Coverage & Robustness (tag: v0.24.0)

### Agent A — tests/ (REG-007..012 + zero-signal fixes + lib_ssh_helpers.bats)

- [-] TEST-012: fix zero-signal assertions in lib_oci_helpers.bats (lines 171, 203, 225, 234, 244, 349)
- [-] TEST-012: fix zero-signal assertions in uninstall_all_datasafe_services.bats (lines 35, 42, 51)
- [-] REG-007: oci_exec stderr isolation test (lib_oci_helpers.bats)
- [-] REG-008: DELETED lifecycle-state target registration test (lib_oci_helpers.bats)
- [-] REG-009: ds_target_update_service.sh PUT semantics test
- [-] REG-010: ds_target_activate.sh multi-target partial-success test
- [-] REG-011: normalize_secret_value path input test (lib_common.bats)
- [-] REG-012: normalize_secret_value literal input test (lib_common.bats)
- [-] Create tests/lib_ssh_helpers.bats

### Agent B — lib/oci_helpers.sh

- [-] ARCH-005/BASH-014: ds_refresh_target → route through oci_exec (line ~1660)
- [-] ARCH-011: eval → printf -v in resolve_compartment_to_vars + resolve_target_to_vars
- [-] BASH-013: add iteration limit to generate_bundle_key unbounded loop
- [-] PERF-002: ds_resolve_target_name accept optional pre-resolved name
- [-] PERF-003: oci_resolve_compartment_ocid in-memory cache
- [-] PERF-004: ds_is_cdb_root_target accept pre-fetched JSON param
- [-] SEC-010: broaden _oci_redact_cmd to mask --credentials, --secret, --auth-token

### Agent C — bin scripts (register + prereqs + move + summary)

- [-] BASH-008: jq --arg in ds_target_register.sh
- [-] BASH-007: compartment name validation in ds_target_register.sh
- [-] ORA-015: Oracle identifier whitelist in ds_database_prereqs.sh
- [-] DEP-006: ORACLE_HOME validation in ds_database_prereqs.sh
- [-] BASH-004: ((count++)) → $(( count + 1 )) in ds_target_move.sh
- [-] DEP-005: require_oci_cli call in ds_target_move.sh
- [-] PERF-001: ENRICH_MISSING=false default in ds_target_connector_summary.sh

### Agent E — PERF-012 bounded parallelism

- [-] PERF-012: bounded parallelism for --mode async in ds_target_refresh.sh
- [-] PERF-012: bounded parallelism for --mode async in ds_target_activate.sh

### Post-agent manual pass

- [ ] BASH-001: move setup_error_handling before init_config in all 21 scripts
- [ ] BASH-001: add setup_error_handling to ds_target_move.sh, ds_version.sh, template.sh
- [ ] BASH-024: empty array nounset-safe expansion pattern at remaining sites
- [ ] make ci passes (all agents merged)
- [ ] CHANGELOG + release notes v0.24.0
- [ ] Bump VERSION to 0.24.0
- [ ] Commit + tag v0.24.0

## M5 — Documentation & Polish (tag: v1.0.0)

*Pending M4 completion + GATE 2 approval*
