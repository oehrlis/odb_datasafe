# Unattended Execution Prompt — odb_datasafe M1 → v1.0.0

> Copy this entire file content as the opening prompt in a new Claude Code session.
> The agent runs M1 through M5 autonomously. Human approval is required only at
> the three predefined gates (marked GATE below).

---

## Mission

Implement the odb_datasafe v0.20.4 → v1.0.0 roadmap. Execute milestones M1 through M5
in order. Each milestone closes with a git tag, a passing `make ci`, and a release-note
entry. All decisions are pre-resolved — no human input is needed between milestones
unless a GATE is reached or something goes sideways.

**Working directory:** `/Users/stefan.oehrli/Repos/own/oehrlis/odb_datasafe`

---

## Context

`odb_datasafe` is a Bash extension for managing Oracle OCI Data Safe targets and
connectors (30 bin scripts, 5 lib modules, ~16,500 LOC, BATS test suite). The full
framework review (v0.20.4) has been completed. All artifacts are under `doc/review/`.

**Master reference:** `doc/review/REVIEW.md` — executive summary, all findings,
roadmap, decisions, and v1.0.0 readiness checklist.

**Roadmap detail:** `doc/review/roadmap.md` — per-milestone tasks, acceptance criteria,
quality gates, and release strategy.

**Findings detail:** `doc/review/findings/` — 9 domain files with file:line evidence.

---

## Resolved Decisions (do not re-ask)

| ID | Decision |
|----|---------|
| D-1 | Installer stays standalone. No `lib/common.sh` integration. Harden in place: regression tests, ERR/EXIT traps, centralized layout discovery. |
| D-2 | bash 4.0+ required. Add `BASH_VERSINFO` guard in `lib/common.sh` at source time (oradba pattern). |
| D-3 | `--grant-mode ALL` stays default. Document privilege surface in prerequisites only. |
| D-4 | CHANGELOG without `[Unreleased]`. Entries written at release time. Backfill 0.19.2/0.19.3/0.19.4 from `doc/release_notes/`. |
| D-5 | Installer runs on Linux AND macOS. `uname -s` OS detection + per-command `command -v` checks. |
| C-1 | `DS_Admin.2025` removed from code in M1. Default to `''`, fail on empty. No git history rewrite. |
| C-2 | Tag after each milestone: v0.21.0 (M1), v0.22.0 (M2), v0.23.0 (M3), v0.24.0 (M4), v1.0.0 (M5). |
| C-3 | PERF-012 and ARCH-013 included in v1.0.0 (M4 and M5 respectively). No deferral. |

---

## Execution Rules

1. **Read before acting.** Before each milestone, read `doc/review/roadmap.md` (the
   full milestone section) and the relevant domain findings files. Never implement
   from memory alone.

2. **Plan → Check-in → Implement.** Write the per-milestone plan to `tasks/todo.md`
   before starting implementation. Mark items complete as you go.

3. **Parallel agents for independent tasks.** Within a milestone, spawn parallel
   subagents for independent work (e.g., SQL change + Makefile change + lib change).
   Use sequential execution when there are dependencies.

4. **Quality gate before advancing.** A milestone is DONE only when its acceptance
   criteria pass AND `make ci` exits 0. Never advance on "looks right" alone.

5. **Commit discipline.** Conventional Commits format: `type(scope): description`.
   Types: feat | fix | docs | refactor | chore | test | ci. No amending published
   commits. No `--no-verify`. One atomic commit per logical unit.

6. **When something goes sideways: stop and re-plan.** Do not push forward. Update
   `tasks/todo.md` with the blocker and the revised approach.

7. **Lessons.** After any correction, update `tasks/lessons.md`.

8. **Tags.** After each milestone's `make ci` passes: `git tag -a vX.Y.Z -m "..."`,
   then `git push origin main && git push origin vX.Y.Z`. Ask before pushing if
   unsure.

---

## GATE 1 — Before M1 commit lands on main

Present the full diff (`git diff --stat`) and confirm:
- A planted failing test makes `make ci` exit non-zero
- `grep -R "DS_Admin.2025" .` returns zero matches
- Human approves the M1 commit before it lands

**After GATE 1 approval:** merge M1, tag v0.21.0, proceed to M2.

---

## M1 — Release Gate Restoration (target: ~2 days → tag v0.21.0)

**Goal:** Restore a working CI/release quality gate. This milestone makes every
subsequent milestone verifiable.

**Read first:**
- `doc/review/roadmap.md` → section "M1 - Release Gate Restoration"
- `doc/review/findings/release.md` (REL-001..REL-007)
- `doc/review/findings/testing.md` (TEST-001)
- `doc/review/findings/bash.md` (BASH-002)
- `doc/review/findings/oracle.md` (ORA-001)
- `doc/review/findings/deps.md` (DEP-001)

**Key changes:**

1. `Makefile:117-129` — remove `|| echo` from non-timeout branch; add `exit $$rc`
   after timeout branch `fi` so bats failures propagate.
2. `.github/workflows/ci.yml:65` — remove `continue-on-error: true`.
3. `Makefile` — add `release:` prerequisite `check` so release cannot run without a
   green lint+test; add `format-check` (shfmt) to the `check`/`ci` chain.
4. SQL templates (`sql/create_ds_admin_user.sql` and any other SQL with the password)
   — change `DS_Admin.2025` default to `''` and add a `WHENEVER SQLERROR EXIT 1` +
   validation block that fails explicitly when password is empty (decision C-1).
5. `lib/common.sh` — add `BASH_VERSINFO` version guard at source time (decision D-2,
   oradba pattern: `[[ ${BASH_VERSINFO[0]} -lt 4 ]] && { echo "ERROR: bash 4.0+ required" >&2; exit 1; }`).
6. `bin/ds_connector_register_oradba.sh` and `bin/ds_connector_update.sh` — add
   `set -euo pipefail` at top and call `setup_error_handling` in `main()` (BASH-002).
7. `README.md` / `doc/index.md` — update "Latest Release" to v0.20.4 (or derive from
   VERSION).
8. `doc/milestone-v1.0.0.md` — create the v1.0.0 readiness checklist file based on
   the checklist in `doc/review/roadmap.md` section "v1.0.0 readiness checklist".

**Acceptance criteria (all must pass):**
- `grep -c "continue-on-error" .github/workflows/ci.yml` == 0
- A planted failing test (`@test "planted" { false; }`) causes `make test` to exit
  non-zero (verify, then remove the planted test)
- `make release` aborts when `make check` fails (dry-run proof)
- `grep -R "DS_Admin.2025" .` == 0 matches
- Running a script under bash 3.2 (or simulated) prints version error and exits 1
- The two BASH-002 scripts contain `set -euo pipefail`
- `doc/milestone-v1.0.0.md` exists

**Tag:** v0.21.0 after GATE 1 human approval.

---

## M2 — Security Hardening (target: 3-5 days → tag v0.22.0)

**Goal:** Eliminate credential exposure on argv/disk; reduce IAM and Oracle privilege
surface to a defensible posture.

**Read first:**
- `doc/review/roadmap.md` → section "M2 - Security Hardening"
- `doc/review/findings/security.md` (SEC-001..SEC-010)
- `doc/review/findings/oracle.md` (ORA-002..ORA-016 relevant items)
- `doc/review/findings/deps.md` (DEP-004, DEP-012)

**Key changes:**

1. Secrets on argv (SEC-002, SEC-003): route through `file://` + `mktemp` + `umask 077`
   + EXIT trap pattern (model: `ds_target_update_credentials.sh`). Emit deprecation
   warning (not hard failure) when plaintext `-P` argv is still used, to give one-
   release migration window.
2. Register payload temp file (SEC-004 = BASH-015): use `mktemp`, `umask 077`, EXIT
   trap removes file even on SIGTERM/SIGINT. On failure, write `****`-masked copy.
3. Config sourcing (SEC-005): validate ownership/permissions before sourcing; log
   which configs are loaded.
4. Broad `chown *` with `|| true` mask (SEC-006 = BASH-023): remove `|| true` mask;
   make chown failure surfaced.
5. `journalctl` sudoers wildcard (SEC-007): narrow the rule, remove trailing `*`.
6. `pkill -f` (SEC-008): constrain to avoid collateral kills.
7. IAM policy (ORA-013, ORA-014): constrain `manage data-safe-family in tenancy`
   with `where target.compartment.id=`; constrain `use keys` + tenancy reads.
8. Oracle profile (ORA-003..ORA-005): `PASSWORD_LOCK_TIME 1`; add finite
   `INACTIVE_ACCOUNT_TIME`; explicit `CONTAINER` scope on profile creation;
   replace `GRANT RESOURCE` with least-privilege grants.
9. SQL injection in `extension_comprehensive.sql` (ORA-009): remove HOST + predictable
   /tmp pattern.
10. Vendor `setup.py` (DEP-004, DEP-012): add Python 3.8+ version check; add
    checksum verification before executing vendor code.
11. D-3: Keep `--grant-mode ALL` default unchanged; write the privilege-surface
    documentation in the prerequisites doc.

**Acceptance criteria:**
- `grep -R "\-P \$" bin/` shows no plaintext secret on argv in non-deprecated form
- Temp credential files use `mktemp`, `umask 077`, EXIT trap — regression test proves
  cleanup on kill
- `grep -R "in tenancy" doc/` shows only constrained IAM policy statements
- SQL: `PASSWORD_LOCK_TIME 1` in profile; `GRANT RESOURCE` replaced
- Vendor `setup.py` call is preceded by checksum check
- Prerequisites doc documents the `--grant-mode ALL` privilege surface
- Full `make ci` passes

**Tag:** v0.22.0

---

## M3 — Installer Hardening (target: 5-8 days → tag v0.23.0)

**Goal:** Make `bin/install_datasafe_service.sh` robust and portable (standalone per
D-1) by centralizing layout discovery, adding ERR/EXIT traps, and supporting Linux +
macOS (D-5).

**Read first:**
- `doc/review/roadmap.md` → section "M3 - Installer Hardening"
- `doc/review/findings/architecture.md` (ARCH-001, ARCH-007, ARCH-008)
- `doc/review/findings/testing.md` (TEST-002..TEST-006, REG-001..REG-006)
- `doc/review/findings/deps.md` (DEP-002, DEP-007)
- `doc/review/findings/bash.md` (BASH-006, BASH-016, BASH-023)

**IMPORTANT:** The regression tests REG-001..REG-006 (from `doc/review/findings/testing.md`
"Required Regression Tests" table) MUST be written BEFORE the installer refactor starts.
They are the safety net. Write them in `tests/install_datasafe_service.bats` first,
verify they run (some may fail now — that is expected and correct), then proceed with
the refactor.

**Key changes:**

1. Regression tests first: REG-001..REG-006 in `tests/install_datasafe_service.bats`
   (see testing.md "Required Regression Tests" table for exact scenarios).
2. Centralize layout discovery: one resolver for Oracle base, connector base, systemd
   paths, sudoers paths — build on `find_connector_base()` introduced in v0.20.4.
3. OS + binary detection (D-5): `uname -s` OS detection (Linux vs Darwin); resolve
   `systemctl`, `visudo`, `getent` via `command -v`; clear actionable error message
   when a required command is absent on the current OS.
4. ERR + EXIT traps (BASH-016): add `trap error_handler ERR` and cleanup trap to
   the installer (it stays standalone — do not source `lib/common.sh`; reimplement
   the minimum trap logic inline).
5. Route non-ERROR output to stderr consistently (BASH-006): all messages from
   `print_message` go to stderr; structured output (file paths, service names) to
   stdout explicitly.
6. `--prepare` → `--install` contract (ARCH-008): `--install` consumes validated
   artifacts; regeneration only through the explicit logged path; no silent mutation.
7. Missing `oradba_dsctl.sh` (DEP-007): hard pre-install validation error when
   REGISTRY_ALIAS mode is set and the binary is absent.

**Acceptance criteria:**
- REG-001..REG-006 all present in the test file and green after refactor
- No hardcoded Oracle/systemd absolute path outside the single resolver
  (`grep -R "/u01/app\|/etc/systemd\|/etc/sudoers.d" bin/install_datasafe_service.sh`
  shows only comments or the resolver itself)
- Installer has active ERR and EXIT traps (inject a failure to verify)
- `--prepare --dry-run` and `--install --dry-run` work on Linux; on macOS mocks confirm
  the absent-command path produces clear error (not a bash crash)
- Full `make ci` passes

**Tag:** v0.23.0

---

## M4 — Test Coverage & Robustness (target: 5-8 days → tag v0.24.0)

**Goal:** Regression tests for all recent defects; fix zero-signal test assertions;
engage strict mode properly; input safety; PERF-012 bounded parallelism.

**Read first:**
- `doc/review/roadmap.md` → section "M4 - Test Coverage & Robustness"
- `doc/review/findings/testing.md` (TEST-007..TEST-015, REG-007..REG-012)
- `doc/review/findings/bash.md` (BASH-001, BASH-004, BASH-007, BASH-008, BASH-013,
  BASH-014, BASH-019, BASH-024)
- `doc/review/findings/performance.md` (PERF-001..PERF-004, PERF-012)
- `doc/review/findings/deps.md` (DEP-005, DEP-006)
- `doc/review/findings/oracle.md` (ORA-015)
- `doc/review/findings/security.md` (SEC-010)

**Split strategy:** This is the largest milestone. Use parallel subagents:
- Agent A: regression tests REG-007..REG-012 + TEST-012 zero-signal fixes
- Agent B: `ssh_helpers.sh` test coverage (TEST-008) + credential function tests (TEST-009)
- Agent C: `ds_refresh_target` `oci_exec` routing (ARCH-005/BASH-014/SEC-010) + input safety (BASH-007, BASH-008, ORA-015)
- Agent D: strict-mode bootstrap (BASH-001) + eval replacement (ARCH-011) + robustness (BASH-004, BASH-013, BASH-024, DEP-005, DEP-006)
- Agent E: performance fixes (PERF-001, PERF-002, PERF-003, PERF-004, PERF-012)

Each agent works on non-overlapping files. Merge sequentially after each completes.

**Key changes:**

1. Regression tests REG-007..REG-012 (see testing.md table): `oci_exec` stderr
   isolation, DELETED-state re-registration, PUT semantics call order, multi-target
   ERR trap, `normalize_secret_value` path vs literal.
2. Remove all `[ "$status" -eq 0 ] || [ "$status" -eq 1 ]` patterns (12 sites in
   `lib_oci_helpers.bats` and `uninstall_all_datasafe_services.bats`). Fix mocks to
   assert correct status.
3. Create `tests/lib_ssh_helpers.bats` covering all four functions in `lib/ssh_helpers.sh`.
4. Route `ds_refresh_target` through `oci_exec` wrapper (removes the `2>&1` bypass
   that reintroduced the FutureWarning-on-stdout bug).
5. Move `setup_error_handling` call to before `init_config` in every script (BASH-001).
6. Replace `eval "${prefix}_OCID=..."` with `printf -v "${prefix}_OCID" '%s' "$input"` (ARCH-011).
7. `jq --arg` in `ds_target_register.sh` lines 905 and 958 (BASH-008).
8. Compartment name validation before OCI `--query` (BASH-007).
9. Identifier whitelist for `--ds-user`/`--pdb` before embedding in SYSDBA SQL (ORA-015).
10. `((count++)) || true` pattern in `ds_target_move.sh` (BASH-004).
11. `generate_bundle_key` iteration limit (BASH-013).
12. Empty array nounset-safe expansion (BASH-024).
13. `require_oci_cli` in `ds_target_move.sh` (DEP-005).
14. `ORACLE_HOME` validation in `ds_database_prereqs.sh` (DEP-006).
15. `ENRICH_MISSING=false` default with `--enrich` opt-in (PERF-001) — release-note this behavior change.
16. Optional `target_name` parameter in bulk functions to skip redundant OCI GET (PERF-002).
17. Compartment OCID cache in `oci_resolve_compartment_ocid` (PERF-003).
18. `ds_is_cdb_root_target` pre-fetched tags parameter (PERF-004).
19. PERF-012: bounded parallelism for `--mode async` bulk operations with configurable `MAX_PARALLEL` (default 4) and `wait` + exit-code collection.

**Acceptance criteria:**
- REG-001..REG-012 all present and green
- `grep -Rc 'status" -eq 0 \] \|\| \[ "\$status" -eq 1' tests/` == 0
- `tests/lib_ssh_helpers.bats` exists; all four functions covered
- `grep -R "2>&1" lib/oci_helpers.sh` shows no raw bypass in `ds_refresh_target`
- `grep -R "eval " lib/ bin/` shows no caller-variable eval
- `ENRICH_MISSING` defaults false; `--enrich` documented
- `--mode async` with `MAX_PARALLEL=2` processes a 4-target mock set without blocking
- Full `make ci` passes

**Tag:** v0.24.0

---

## M5 — Documentation & Polish (target: 2-3 days → tag v1.0.0)

**Goal:** Eliminate documentation drift, finalize CHANGELOG backfill, fix portability
and cleanup items, and pass the v1.0.0 readiness checklist.

**Read first:**
- `doc/review/roadmap.md` → section "M5 - Documentation & Polish"
- `doc/review/findings/docs.md` (all DOC-001..DOC-016)
- `doc/review/findings/release.md` (REL-004, REL-005, REL-008..REL-012)
- `doc/review/findings/architecture.md` (ARCH-002..ARCH-006, ARCH-010, ARCH-012, ARCH-013)
- `doc/review/findings/deps.md` (DEP-003, DEP-008..DEP-010, DEP-013)
- `doc/review/findings/performance.md` (PERF-005..PERF-011)
- `doc/review/findings/bash.md` (BASH-005, BASH-009, BASH-018)

**Key changes:**

1. CHANGELOG: backfill 0.19.2, 0.19.3, 0.19.4 from `doc/release_notes/` files;
   remove `[Unreleased]` section; write current-milestone entry (D-4).
2. Version single source of truth: Makefile updates script headers on bump;
   remove stale literals v0.19.1 (headers), v1.1.0 (installer SCRIPT_VERSION),
   v4.0.0 (lib/README); derive README "Latest Release" from VERSION file.
3. Doc accuracy: `--remove` → `--uninstall` (DOC-005, two docs); test count
   reconciliation to single value (DOC-002); script count "16+" → "30" (DOC-003);
   add `--prepare`/`--install`/`--uninstall` to options table (DOC-006); document
   CONNECTOR_BASE auto-discovery (DOC-007); fix broken link to v0.19.0.md (DOC-008);
   replace `etc/.env.example` with `etc/datasafe.conf.example` (DOC-009);
   update lib/README.md framing (DOC-010); fix doc/testing.md version + counts
   (DOC-011); fix tests/README.md version + table (DOC-012).
4. Config naming alignment (ARCH-006): one canonical filename across loader/example/docs.
5. Code dedup: delete duplicate `is_ocid` from `lib/oci_helpers.sh` (ARCH-003);
   delete `_ds_cache_mtime`, repoint caller at `_ds_file_mtime` (ARCH-004);
   extract shared bootstrap version-grep into a helper or replace with
   `read -r SCRIPT_VERSION < "${SCRIPT_DIR}/../VERSION"` (ARCH-002/PERF-008);
   replace `ds_database_prereqs.sh` duplicated logging block with source from
   lib/common.sh (DEP-013).
6. ARCH-013: move Data Safe domain logic (ds_* functions) from `lib/oci_helpers.sh`
   into `lib/ds_lib.sh` where it belongs; update all callers.
7. Portability: `grep -oP` → `grep -oE` in `ds_connector_update.sh` (DEP-003).
8. Release hygiene: drop redundant `make test` in `release.yml` (REL-008); pin
   tarball timestamp for reproducibility (REL-009).
9. Onboarding doc for `ds_connector_create.sh` — add a usage section to
   `doc/install_datasafe_service.md` (DOC-016).
10. Subshell reduction: PERF-005/006/009 (jq single-pass display), PERF-011
    (`${var^^}` for lifecycle normalization), BASH-009 (`echo|tr` → builtins),
    BASH-018 (`LC_ALL=C` on tr calls), BASH-005 (`((frame++)) || true`).
11. Permanently skipped tests: implement or remove (TEST-016, 3 tests in
    `edge_case_tests.bats`).

**GATE 2 — Before v1.0.0 tag:**

Run through `doc/milestone-v1.0.0.md` checklist line by line. Every item must be
confirmed green. Present summary to human and await approval before tagging v1.0.0.

**Acceptance criteria (all must pass before GATE 2):**
- CHANGELOG has 0.19.2/0.19.3/0.19.4 entries; no `[Unreleased]` section
- `grep -R "\-\-remove" doc/ README.md` == 0
- `grep -R "v0.19.1\|v1.1.0\|v4.0.0" doc/ lib/README.md` == 0 (stale version strings)
- `grep -R "grep -oP" bin/ lib/` == 0
- markdownlint clean across all touched docs
- Single consistent test count across README, doc/testing.md, tests/README.md
- `doc/milestone-v1.0.0.md` checklist: every item checked
- Full `make ci` passes

**Tag:** v1.0.0 after GATE 2 human approval.

---

## GATE 3 — If scope change is needed

If any milestone surfaces a finding requiring scope beyond the decisions above
(e.g., M4 needs splitting, a new blocker is discovered, a dependency fails), STOP,
document the blocker in `tasks/todo.md` with a "BLOCKED:" prefix, and present to
the human. Do not push forward past a blocker.

---

## Done Signal

The session is complete when:
- `git log --oneline -5` shows the v1.0.0 tag
- `doc/milestone-v1.0.0.md` has all items checked
- GATE 2 human approval is on record
- `make ci` exits 0 on a clean checkout of v1.0.0
