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

## M3 — Installer Hardening (tag: v0.23.0)

**Goal:** Harden the installer to production deployment standards.

### Tasks

- [x] Read M3 findings (architecture.md ARCH-001/007/008, bash.md BASH-006/016/023, deps.md DEP-002/007, testing.md REG-001..006)
- [x] Write REG-001..REG-006 regression tests in tests/install_datasafe_service.bats
  - REG-001 PASS: auto-discovers connector via ORACLE_BASE
  - REG-002 PASS: exits non-zero when connector not found
  - REG-003 SKIP: auto-regen chown fails in test env (M3 fix: respect DRY_RUN in chown - ARCH-008)
  - REG-004 PASS: warns when sudoers file missing
  - REG-005 PASS: warns when ExecStart binary missing
  - REG-006 SKIP: log dir creation unreachable via dry-run (M3 fix: move into plan section - BASH-016)
- [ ] ARCH-007/DEP-002: centralize layout discovery; resolve systemctl/visudo/getent via command -v; OS detection uname -s (Linux vs Darwin)
- [ ] BASH-016: add ERR + EXIT traps to installer (standalone, no lib/common.sh)
- [ ] BASH-006: route non-ERROR output to stderr consistently; structured output to stdout
- [ ] ARCH-008: --prepare → --install contract; --install must not regenerate --prepare artifacts except via explicit logged path; fix DRY_RUN chown skip (unblocks REG-003)
- [ ] DEP-007: missing oradba_dsctl.sh is a hard pre-install validation error (unblocks existing WARNING)
- [ ] Move log dir creation into dry-run plan section (unblocks REG-006)
- [ ] Remove REG-003 and REG-006 skip markers after above fixes
- [ ] CHANGELOG + release notes v0.23.0
- [ ] make ci passes → commit + tag v0.23.0

## M4 — Test Coverage & Robustness (tag: v0.24.0)

*Pending M3 completion*

## M5 — Documentation & Polish (tag: v1.0.0)

*Pending M4 completion + GATE 2 approval*
