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

## M2 — Security Hardening (tag: v0.22.0)

*Pending M1 completion*

## M3 — Installer Hardening (tag: v0.23.0)

*Pending M2 completion*

## M4 — Test Coverage & Robustness (tag: v0.24.0)

*Pending M3 completion*

## M5 — Documentation & Polish (tag: v1.0.0)

*Pending M4 completion + GATE 2 approval*
