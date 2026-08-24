# odb_datasafe - Active Tasks

## v1.1.0 - Audit reconcile + trail report (2026-08-23, done)

Context: Splunk SIEM integration. 1390 Data Safe targets (Prod 600 / QS 393 /
Test 397). Prod is the rollout scope. 54 targets tenancy-wide without
`DBSec.ContainerStage`, 506 Prod trails `NOT_STARTED`, 31 Prod targets with no
trail object at all.

### Decisions (confirmed 2026-08-23)

1. Missing trail objects are created via `oci data-safe audit-profile
   discover-audit-trails` - there is no `audit-trail create`. Fire and forget,
   no work-request wait; the trail is started by the next wave.
2. The trail state report is its own script, `bin/ds_trail_report.sh`.
3. `--limit N` counts every write globally (tag update, discovery, trail start
   each count 1), one shared budget consumed in step order.
4. The `lifecycle-state` vs `status` defect in `ds_target_audit_trail.sh` is
   fixed as part of this change.

### Tasks

- [x] Fix `ds_target_audit_trail.sh`: evaluate `status` next to `lifecycle-state`
- [x] `lib/ds_lib.sh`: bulk helpers for audit trails and audit profiles
- [x] `bin/ds_find_untagged_targets.sh`: `-k`/`--tag-key` for key-level checks
- [x] New `bin/ds_trail_report.sh` (table/csv/json, grouped by environment)
- [x] New `bin/ds_audit_reconcile.sh` (dry-run default, `--apply`, `--limit`)
- [x] 61 new BATS tests, including the trail-status regression
- [x] Docs: `doc/audit_reconcile.md`, quickref, doc index, README
- [x] VERSION 1.0.10 -> 1.1.0 + CHANGELOG entry
- [x] `make lint`, `make format-check`, `make test` - 414 pass, 0 fail

### Results

Two defects were found and fixed along the way, both pre-existing:

- `ds_target_audit_trail.sh` read only `lifecycle-state`. Collection progress
  lives in `status`, so `--list` could never report `NOT_STARTED` and the skip
  check never matched - every run re-issued a start for trails that were
  already collecting.
- `ds_find_untagged_targets.sh -o csv` piped `@csv` output back into
  `jq -r '.'` and aborted with a parse error on any non-empty row.

One defect was found in new code during testing: `take_budget` was called in a
command substitution, so the shared `--limit` budget was never decremented and
every step got the full budget. Now sets a global instead.

### Not done, deliberately

- No security policy distribution (Data Safe handles that via target groups)
- No deleting or stopping of trails
- No automatic handling of `NEEDS_ATTENTION` beyond reporting
- No backfill of historic audit data

---

## v1.0.8 — Create+Delete path for vm-cluster-id change (2026-07-03)

**Problem:** `ds_target_reregister.sh --cluster` fails with OCI 400 "vmClusterId cannot be updated".
OCI Data Safe API prohibits changing `vm-cluster-id` via `target-database update`. Requires Delete+Create.

- [x] Add new globals: `NEW_TARGET_OCID`, `CUR_CONNECTION_OPTION`, `CUR_TLS_CONFIG`, `CUR_FREEFORM_TAGS`, `CUR_DEFINED_TAGS`
- [x] Extend `load_current_target()` to capture connection-option, tls-config, tags
- [x] Update `show_reregister_plan()`: show CREATE+DELETE strategy when cluster changes
- [x] Rename `do_reregister()` → `do_reregister_update()` (existing update path)
- [x] Add `do_reregister_create_delete()`: CREATE new target → DELETE old
- [x] Add `do_reregister()` router: detect cluster change → dispatch
- [x] CHANGELOG v1.0.8 + release notes
- [x] Run `make lint && make test` — all green
- [x] Release v1.0.8

---

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
- [x] Verify acceptance criteria (GATE 1) — make ci running
- [x] GATE 1: present diff for human approval
- [x] Commit + tag v0.21.0 (after approval)

### Acceptance Criteria

- [x] Planted failing test causes make test to exit non-zero
- [x] grep -c "continue-on-error" .github/workflows/ci.yml == 0
- [x] make release aborts when make check fails
- [x] grep -R "DS_Admin.2025" . == 0 matches
- [x] bash 4.0+ guard active in lib/common.sh
- [x] ds_connector_register_oradba.sh and ds_connector_update.sh have set -euo pipefail
- [x] doc/milestone-v1.0.0.md exists

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

## M4 — Test Coverage & Robustness (tag: v0.24.0) ✓ DONE

- [x] TEST-012: fix zero-signal assertions in lib_oci_helpers.bats + uninstall bats
- [x] REG-007..REG-012: all six new regression tests added and green
- [x] Create tests/lib_ssh_helpers.bats (17 tests)
- [x] ARCH-005/BASH-014, ARCH-011, BASH-013, PERF-002/003/004, SEC-010 in oci_helpers.sh
- [x] BASH-008, BASH-007, ORA-015, DEP-006 in bin scripts
- [x] BASH-004, DEP-005, PERF-001 in ds_target_move.sh + ds_target_connector_summary.sh
- [x] PERF-012: bounded parallelism for --mode async in refresh + activate
- [x] BASH-001: setup_error_handling before init_config in all 24 scripts
- [x] make ci passes — 349 tests, 0 failures
- [x] CHANGELOG + release notes v0.24.0
- [x] Bump VERSION to 0.24.0
- [x] Commit 92763b1 + tag v0.24.0

## M5 — Documentation & Polish (tag: v1.0.0)

### Agent A — Documentation + CHANGELOG + version strings

- [x] DOC-002: fix contradictory test counts in README.md (use 346)
- [x] DOC-003: fix script count "16+" → "30" in README.md + doc/index.md
- [x] DOC-005: --remove → --uninstall in doc/install_datasafe_service.md + quickstart
- [x] DOC-006: add --prepare/--install/--uninstall to options table
- [x] DOC-007: document CONNECTOR_BASE auto-discovery
- [x] DOC-008: fix broken link v0.19.0.md → v0.19.1.md in doc/index.md
- [x] DOC-009: etc/.env.example → etc/datasafe.conf.example in doc/index.md + standalone
- [x] DOC-010: lib/README.md v4.0.0 removed, LOC updated, ssh_helpers.sh added
- [x] DOC-011: doc/testing.md version 0.7.1 → v0.24.0, reconcile counts
- [x] DOC-012: tests/README.md v0.9.0 → v0.24.0, update coverage table
- [x] DOC-013: CHANGELOG backfill 0.19.2/0.19.3/0.19.4 + remove [Unreleased]
- [x] DOC-014: remove "new in v0.6.1" from README
- [x] DOC-016: add ds_connector_create.sh usage to doc/index.md
- [x] REL-005: fix SCRIPT_VERSION v1.1.0 in install + uninstall scripts
- [x] REL-008: remove redundant `make test` from .github/workflows/release.yml
- [x] REL-009: remove timestamp from .extension.checksum in scripts/build.sh

### Agent B — lib/ refactor (ARCH-013 + dedup + perf)

- [x] ARCH-013: move ds_* functions from lib/oci_helpers.sh → lib/ds_lib.sh
- [x] ARCH-003: remove duplicate is_ocid from lib/oci_helpers.sh
- [x] ARCH-004: delete _ds_cache_mtime, repoint to _ds_file_mtime
- [x] Update tests/lib_oci_helpers.bats: ds_* tests source ds_lib.sh

### Agent C — Small fixes + bash + portability

- [x] BASH-005: ((frame++)) || true in lib/common.sh
- [x] BASH-018: LC_ALL=C at top of lib/common.sh
- [x] DEP-003: grep -oP → grep -oE in bin/ds_connector_update.sh
- [x] PERF-007: sort|uniq-c|sort → jq in bin/ds_target_list.sh
- [x] TEST-016: remove 3 permanently skipped tests from tests/edge_case_tests.bats

### Post-agent

- [x] make ci passes (346 tests, 0 failures)
- [x] Update doc/milestone-v1.0.0.md checklist
- [x] GATE 2: human approval received 2026-06-28
- [x] Bump VERSION to 1.0.0
- [x] CHANGELOG entry v1.0.0
- [x] Create doc/release_notes/v1.0.0.md
- [x] Commit f88f772 + tag v1.0.0 (commit 4b56bb6)
