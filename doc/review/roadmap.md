# Implementation Roadmap - odb_datasafe v0.20.4 -> v1.0.0

> Supersedes: this roadmap REPLACES any prior `.claude/review-plan.md` (none was
> present in the repository at the time of writing - if one is later restored,
> this file is authoritative and the older plan is void). It operationalises the
> Phase 1-3 review artifacts:
> `doc/review/consolidated-findings.md`, `doc/review/technical-debt-register.md`,
> `doc/review/risk-register.md`, and the nine domain files in
> `doc/review/findings/`.

## Overview

This roadmap converts 107 canonical findings (~76.5 engineer-days raw) into five
ordered, independently verifiable milestones taking odb_datasafe from v0.20.4 to
v1.0.0. Milestones are sequenced so the release/CI gate is restored first (M1),
then the nine v1.0.0 blockers from the risk register are cleared across M1-M3,
followed by broad test/robustness hardening (M4) and documentation polish (M5).
Decisions D-1 through D-5 (installer stays standalone; bash 4.0+ required;
`--grant-mode ALL` stays default; no `[Unreleased]` section; installer runs on
Linux AND macOS) are baked into the scope below and override the corresponding
"Default if no answer" entries in the consolidated findings.

Effort legend: S = <=4h (one sitting); M = 1-2 days; L = ~1 week; XL = multi-week
(scope-negotiation flag). Per-milestone sums are deliberately realistic, not
optimistic.

## Decision deltas vs. consolidated findings

The following decisions change the recorded defaults; all milestone scope reflects
the decision, not the original finding text.

<!-- markdownlint-disable MD013 MD060 -->
| Decision | Finding default | Adopted scope |
|----------|-----------------|---------------|
| D-1 | (b) tests + minimal hardening, defer integration | Installer stays standalone permanently; no `lib/common.sh` integration. Harden in place: regression tests, ERR/EXIT traps, centralized layout discovery |
| D-2 | (a) require 4.0+ | `BASH_VERSINFO` guard in `lib/common.sh` at source time (oradba pattern); macOS users install bash 4+ via Homebrew |
| D-3 | (a) least-privilege default | `--grant-mode ALL` STAYS default; document the privilege surface in prerequisites only - ORA-006/ORA-007 reduce to documentation tasks |
| D-4 | adopt `[Unreleased]` | NO `[Unreleased]` section; entries written at release time; backfill 0.19.2/0.19.3/0.19.4 from existing release notes |
| D-5 | Linux-only `uname -s` guard | Installer supports Linux AND macOS; `uname -s` OS detection plus per-command `command -v` checks for `systemctl`/`visudo`/`getent`; clear error when a required command is absent |
<!-- markdownlint-enable MD013 MD060 -->

---

## Milestone Plan

### M1 - Release Gate Restoration (target: 1-2 days)

**Goal:** Restore a working CI/release quality gate and close the credential and
release blockers so every subsequent PR is actually verified, deliverable in a
single PR.

**Findings addressed**

<!-- markdownlint-disable MD013 MD060 -->
| ID | Title | Effort | Cluster |
|----|-------|--------|---------|
| REL-001 (=TEST-001, REL-002) | `make test`/CI mask bats exit code | S | A |
| REL-007 | `make release` runs without lint/test gate | S | A |
| REL-003 | shfmt format-check absent from CI | S | A |
| REL-006 | Same-day patch cadence - no pre-release gate | M | A |
| REL-010 | No documented v1.0.0 readiness checklist | M | A |
| ORA-001 (=SEC-001) | Hardcoded default password `DS_Admin.2025` in SQL | S | B |
| DEP-001 (=DEP-011, BASH-021) | No bash 4.0+ runtime guard (D-2) | S | D |
| BASH-002 (=SEC-009) | 2 scripts have zero error protection | S | E |
| DOC-001 | README/index "Latest Release" stale | S | I |
<!-- markdownlint-enable MD013 MD060 -->

Effort sum: 5xS + 2xM = ~3.5 days raw; realistic 1-2 days with the edits being
mostly one-liners and the checklist being prose.

**Implementation tasks**

1. `Makefile:117-129` - remove `|| echo` from the non-timeout test branch; add
   `exit $$rc` after the timeout branch `fi` so a failing bats run propagates.
2. `.github/workflows/ci.yml:65` - remove `continue-on-error: true`.
3. `Makefile` - add `release: check version-bump-patch tag` so a release cannot
   proceed without a green `lint test`; add `format-check` to the `check`/`ci`
   chain as a hard gate.
4. `bin/*sql*` / SQL templates - change the hardcoded admin password default to
   `''` and fail with an explicit `&2` error when empty; rotate any deployed
   account out of band; document the credential-purge note.
5. `lib/common.sh` - add a `BASH_VERSINFO` guard at source time (oradba pattern),
   emitting a clear error and exit when `BASH_VERSINFO[0] < 4` (D-2).
6. Add `set -euo pipefail` plus `setup_error_handling` to the two unprotected
   scripts named in BASH-002.
7. `README.md` / docs index - set "Latest Release" derived from the `VERSION`
   file.
8. Author `doc/milestone-v1.0.0.md` - the v1.0.0 readiness checklist (REL-010,
   pass/fail criteria) referenced by the release strategy below.

**Dependencies:** none - this is the entry milestone and gates all others.

**Acceptance criteria (measurable)**

- [ ] A deliberately failing bats test causes `make test`, `make check`, and
      `make ci` to exit non-zero (verified by a throwaway failing assertion).
- [ ] CI job fails (red) on a failing test - no `continue-on-error` remains in
      `ci.yml` (`grep -c continue-on-error .github/workflows/ci.yml` == 0).
- [ ] `make release` aborts when `make check` fails (dry-run proof).
- [ ] `grep -R "DS_Admin.2025"` across the repo == 0 matches.
- [ ] Running any framework script under bash 3.2 prints the version error and
      exits non-zero; under bash 4+ it proceeds.
- [ ] The two BASH-002 scripts contain `set -euo pipefail`.
- [ ] `doc/milestone-v1.0.0.md` exists with explicit pass/fail criteria.

**Risks:** Enabling the gate may surface pre-existing red tests (expected) - they
are triaged into M4 unless they are blockers. Password default change must not
break a legitimate non-empty supply path - covered by a dry-run test.

**Quality gate:** standardized gate (see Quality Gates), with the special note
that this is the milestone that makes the gate functional - it must self-verify
by demonstrating a failing test now fails CI.

**Expected artifacts:** modified `Makefile`, `.github/workflows/ci.yml`,
`lib/common.sh`, SQL template(s), two hardened scripts, updated `README.md`, new
`doc/milestone-v1.0.0.md`, CHANGELOG/release-notes entries, version bump, one
atomic commit.

---

### M2 - Security Hardening (target: 3-5 days)

**Goal:** Eliminate credential exposure on argv/disk and reduce the IAM/Oracle
privilege and config-trust surface to a defensible posture.

**Findings addressed**

<!-- markdownlint-disable MD013 MD060 -->
| ID | Title | Effort | Cluster |
|----|-------|--------|---------|
| SEC-002 (=ORA-002) | DB secret on command line, visible in `ps` | S | B |
| SEC-003 | Bundle password on OCI CLI argv | S | B |
| SEC-004 (=BASH-015) | Predictable /tmp register payload, plaintext, no trap | S | B |
| SEC-005 | Config files sourced without ownership checks | M | J |
| SEC-006 (=BASH-023) | Broad `chown *` with `|| true` during root install | S | C |
| SEC-007 | `journalctl` sudoers trailing `*` wildcard | S | C |
| SEC-008 | `pkill -f` by path can kill unintended processes | S | - |
| ORA-013 | `manage data-safe-family in tenancy` over-broad IAM | S | - |
| ORA-003 | `PASSWORD_LOCK_TIME` 5 min vs CIS 1 day | S | - |
| ORA-004 | Profile created without explicit `CONTAINER` scope | S | - |
| ORA-005 | `GRANT RESOURCE` over-broad for service account | S | - |
| ORA-006 | `--grant-mode ALL` ANY-priv grants (D-3: doc only) | S | - |
| ORA-007 | `DS_GRANT_MODE=ALL` default (D-3: doc only) | S | - |
| ORA-009 | HOST + predictable /tmp in extension_comprehensive.sql | S | K |
| ORA-014 | Service account `use keys` + tenancy reads | S | - |
| DEP-004 | `python3` runs vendor `setup.py`, no version check | S | C |
| DEP-012 (=DEP-004) | Vendor `setup.py` no checksum verification | M | C |
<!-- markdownlint-enable MD013 MD060 -->

Effort sum: 15xS + 2xM = ~9.5 days raw; realistic 3-5 days (most S items are
adjacent edits to the same scripts and SQL templates).

**Implementation tasks**

1. Route every secret through the existing safe pattern
   (`--credentials file://<mktemp>` from `ds_target_update_credentials.sh`):
   `mktemp` + `umask 077` + EXIT trap; warn when `-P`/plaintext argv is used and
   steer to `--secret-file` / `read -rs` / `file://` (SEC-002, SEC-003, SEC-004).
2. Validate config file ownership/permissions before sourcing; log which configs
   load (SEC-005, ties to Cluster J in M5).
3. Replace masked broad `chown *` and remove the `|| true` mask so a chown
   failure is surfaced (SEC-006); narrow the sudoers `journalctl` rule, removing
   the trailing `*` (SEC-007).
4. Constrain `pkill -f` to avoid collateral process kills (SEC-008).
5. Constrain `manage data-safe-family in tenancy` with
   `where target.compartment.id=` per the existing JSON example (ORA-013);
   constrain `use keys` + tenancy reads (ORA-014).
6. Set `PASSWORD_LOCK_TIME 1` and a finite `INACTIVE_ACCOUNT_TIME` (ORA-003);
   add explicit `CONTAINER` scope to profile creation (ORA-004); replace
   `GRANT RESOURCE` with least-privilege grants (ORA-005).
7. Remove HOST + predictable /tmp usage from `extension_comprehensive.sql`
   (ORA-009).
8. Add vendor `setup.py` version check and checksum verification before
   execution (DEP-004, DEP-012).
9. D-3: keep `--grant-mode ALL` default unchanged; document the full privilege
   surface in the prerequisites doc (closes ORA-006/ORA-007 as documentation).

**Dependencies:** M1 complete (gate must be live so these fixes are verified).

**Acceptance criteria (measurable)**

- [ ] `grep -R "\-P \$" bin/` and process-argv inspection show no secret passed
      on argv; a regression test asserts secrets go via `file://`/`mktemp`.
- [ ] Temp credential files use `mktemp`, `umask 077`, and are removed by an EXIT
      trap even on failure (test: kill mid-run, assert no plaintext left).
- [ ] Config sourcing rejects world-writable / non-owner files (test).
- [ ] `grep -R "in tenancy" policy*` shows constrained statements only.
- [ ] SQL: `PASSWORD_LOCK_TIME 1` present; no `GRANT RESOURCE` to service user.
- [ ] Vendor `setup.py` invocation is preceded by a checksum check (test).
- [ ] Prerequisites doc documents the `--grant-mode ALL` privilege surface.

**Risks:** Behaviour changes for operators currently passing `-P` (mitigated by
warning, not hard failure, for one release). ORA-003/004/005 alter created
account semantics - release-note prominently.

**Quality gate:** standardized gate; regression tests for every credential-path
change.

**Expected artifacts:** hardened secret-handling in target/connector scripts,
config-loader guard, sudoers template, IAM policy templates, SQL profile/grant
templates, vendor-install checksum logic, prerequisites doc update,
CHANGELOG/release notes, version bump, one atomic commit (or one per logical
group if the PR is split - each its own gate pass).

---

### M3 - Installer Hardening (target: 5-8 days)

**Goal:** Make `bin/install_datasafe_service.sh` robust and portable in place
(standalone, per D-1) by centralizing layout/binary discovery, adding ERR/EXIT
traps, moving validation earlier, and adding Linux+macOS OS detection (D-5) -
WITHOUT integrating the framework.

**Findings addressed**

<!-- markdownlint-disable MD013 MD060 -->
| ID | Title | Effort | Cluster |
|----|-------|--------|---------|
| ARCH-007 (=DEP-002, DEP-007) | Hardcoded Oracle/systemd paths - defect root cause | L | C |
| ARCH-001 (=BASH-016, BASH-006) | Installer god script; no ERR/EXIT trap (in-place, D-1) | L | C |
| ARCH-008 | `--install` mutates `--prepare` artifacts (leaky) | M | C |
| BASH-016 | Installer no ERR/EXIT trap | S | C |
| BASH-006 | Installer non-ERROR messages to stdout | S | C |
| BASH-023 (=SEC-006) | Auto-regen mid-install, chown failure masked | S | C |
| DEP-002 | `systemctl`/`visudo`/`getent` unchecked (D-5: per-command) | S | C |
| DEP-007 | Missing `oradba_dsctl.sh` -> broken unit (non-fatal) | S | C |
<!-- markdownlint-enable MD013 MD060 -->

Effort sum: 2xL + 1xM + 4xS = ~7 days raw; realistic 5-8 days. ARCH-001 is
downgraded from XL to L by D-1 (in-place hardening, not framework integration).

**Implementation tasks**

1. Centralize layout discovery: a single resolver for Oracle base, connector
   base, systemd paths, sudoers paths - one place to change, used everywhere
   (ARCH-007). Build on the existing `find_connector_base()` (v0.20.4).
2. Resolve external binaries via `command -v` for `systemctl`, `visudo`,
   `getent`; add `uname -s` OS detection (Linux vs Darwin) and surface a clear,
   actionable error when a required command is absent on the current OS (D-5,
   DEP-002).
3. Add ERR and EXIT traps to the installer (BASH-016); route non-ERROR output to
   stdout / errors to stderr consistently (BASH-006).
4. Move all environment/path/user validation into `--prepare` so `--install`
   consumes validated artifacts instead of re-deriving and mutating them
   (ARCH-008); stop `--install` from rewriting `--prepare` outputs except via an
   explicit, logged regeneration path.
5. Surface (not mask) chown failures during root install (BASH-023, links
   SEC-006 from M2).
6. Make a missing `oradba_dsctl.sh` a hard, pre-install validation error rather
   than a silently broken unit (DEP-007).

**Dependencies:** M1 (gate) AND the M1 installer regression tests REG-001..REG-006
must exist and pass before refactoring - they are the safety net for this
milestone. M2 (SEC-006 chown handling) should land first to avoid a merge
conflict in the install path.

**Acceptance criteria (measurable)**

- [ ] No hardcoded Oracle/systemd/sudoers absolute path remains outside the
      single resolver (grep audit documented in the PR).
- [ ] Installer runs `--prepare`/`--install --dry-run` successfully on Linux and
      on macOS; on macOS the absent `systemctl`/`visudo`/`getent` produce a clear
      named error, not a stack trace (D-5, tested on both via mocks).
- [ ] Installer has active ERR and EXIT traps (verified by injecting a failure).
- [ ] `--install` does not regenerate `--prepare` artifacts except through the
      explicit logged path (REG-003 still green).
- [ ] Missing `oradba_dsctl.sh` aborts `--prepare`/`--install` with a clear
      error (test).
- [ ] All six installer regression tests REG-001..REG-006 remain green after the
      refactor.

**Risks:** Highest-risk milestone pre-1.0 - the installer is the recurring defect
engine. Mitigated by D-1 (no framework integration) and the M1 regression-test
net. macOS/BSD differences in `getent`/`systemctl` absence must be tested, not
assumed.

**Quality gate:** standardized gate, run on BOTH Linux and macOS; ShellCheck
`--shell=bash` clean; the full REG-001..REG-006 suite green.

**Expected artifacts:** refactored `bin/install_datasafe_service.sh`, layout
resolver, OS/binary detection block, updated unit-file generation, installer docs
touch-up, CHANGELOG/release notes, version bump, one atomic commit.

---

### M4 - Test Coverage & Robustness (target: 5-8 days)

**Goal:** Close the regression-test debt for every recently shipped defect, raise
real test signal, and engage strict-mode/error handling consistently across the
framework.

**Findings addressed**

<!-- markdownlint-disable MD013 MD060 -->
| ID | Title | Effort | Cluster |
|----|-------|--------|---------|
| TEST-002 | `find_connector_base()` no coverage (REG-001/002) | M | C |
| TEST-003 | User= mismatch auto-regen no test (REG-003) | M | C |
| TEST-004 | Missing sudoers warning - no test (REG-004) | S | C |
| TEST-005 | ExecStart binary validation - no test (REG-005) | S | C |
| TEST-006 | Log directory creation - no test (REG-006) | S | C |
| TEST-007 (=ARCH-005, BASH-014, SEC-010) | `oci_exec` stderr isolation - no regression (REG-007) | M | G |
| TEST-008 | `ssh_helpers.sh` entirely untested | M | - |
| TEST-009 | Credential decode/normalize untested (REG-011/012) | M | - |
| TEST-010 | DELETED-state target fix - no regression (REG-008) | S | - |
| TEST-011 | PUT-semantics fix - no regression (REG-009) | S | - |
| TEST-012 | 12 assertions accept status 0 or 1 - zero signal | M | - |
| TEST-013 | ERR-trap multi-target loop fix - no regression (REG-010) | S | - |
| TEST-014 | Integration test exclusion inconsistent | S | - |
| TEST-015 | `lib_common.bats` teardown leaks state | S | - |
| ARCH-005 | `ds_refresh_target` bypasses `oci_exec` | M | G |
| BASH-014 | `ds_refresh_target` `2>&1` bypass | M | G |
| BASH-001 (=ARCH-009, BASH-003) | `setup_error_handling` deferred | M | E |
| ARCH-011 (=BASH-019) | `resolve_*_to_vars` uses eval | S | F |
| BASH-004 | Bare `((count++))` under `set -e` | S | - |
| BASH-007 | OCI `--query` unsanitized compartment name | S | K |
| BASH-008 | jq filter embeds shell vars | S | K |
| BASH-013 | `generate_bundle_key` unbounded loop | S | - |
| BASH-024 | Empty array unsafe under `set -u` | S | - |
| ORA-015 | `--ds-user`/`--pdb` not whitelisted before SQL | S | K |
| SEC-010 | Log redaction incomplete | S | G |
| DEP-005 | `ds_target_move.sh` missing `require_oci_cli()` | S | - |
| DEP-006 | `sqlplus` needs `ORACLE_HOME`, not validated | S | - |
| PERF-001 | Default-on per-target OCI GET enrichment, O(N) | S | - |
| PERF-002 | `ds_resolve_target_name` extra OCI GET per target | M | - |
| PERF-003 | `oci_resolve_compartment_ocid` 3x, no cache | S | - |
| PERF-004 | `ds_is_cdb_root_target` per-target GET | M | - |
<!-- markdownlint-enable MD013 MD060 -->

Effort sum: ~22 days raw; realistic 5-8 days only if parallelized across agents
(regression tests, library tests, robustness fixes, and perf are largely
independent). XL-flag note: this milestone is the largest by raw effort - if 8
days proves tight, split into M4a (regression tests REG-001..REG-012 + TEST-012
signal fixes) and M4b (robustness + perf). REG-001..REG-006 are scheduled here
but MUST be authored before M3 starts (see M3 dependencies).

**Implementation tasks**

1. Author regression tests REG-001 through REG-012 exactly per
   `doc/review/findings/testing.md` "Required Regression Tests" table.
2. Remove every `[ "$status" -eq 0 ] || [ "$status" -eq 1 ]` (12 sites) - fix the
   mock to assert the real status (TEST-012).
3. Create `tests/lib_ssh_helpers.bats` covering all four ssh functions incl.
   tool-not-found, failure, stderr isolation (TEST-008).
4. Route `ds_refresh_target` through `oci_exec`; broaden `_oci_redact_cmd`
   (ARCH-005, BASH-014, SEC-010, anchored by REG-007).
5. Engage strict mode + ERR trap in the shared bootstrap so it runs before
   config/arg parsing (BASH-001); replace `eval` with `printf -v` (ARCH-011).
6. Input-safety: `jq --arg`, JMESPath structured search, identifier whitelisting
   for `--ds-user`/`--pdb` (BASH-007, BASH-008, ORA-015).
7. Robustness fixes: BASH-004, BASH-013, BASH-024, DEP-005, DEP-006.
8. Performance: default `ENRICH_MISSING=false` with opt-in `--enrich` (PERF-001);
   accept optional `target_name` (PERF-002); compartment OCID cache (PERF-003);
   reduce per-target GETs (PERF-004).
9. Test infra: consistent integration-test exclusion (TEST-014); fix
   `lib_common.bats` teardown leak (TEST-015).

**Dependencies:** M1 (gate). REG-001..REG-006 are a prerequisite for M3 and so
must be produced at the front of M4 (or in a small M4-pre PR) before the M3
refactor lands.

**Acceptance criteria (measurable)**

- [ ] REG-001..REG-012 all present and green; each maps to a named commit/defect.
- [ ] `grep -Rc 'status" -eq 0 ] || \[ "\$status" -eq 1' tests/` == 0.
- [ ] `tests/lib_ssh_helpers.bats` exists and covers all four functions.
- [ ] `grep -R "2>&1" bin/ds_refresh_target*` shows no raw bypass (routed via
      `oci_exec`); REG-007 green.
- [ ] `grep -R "eval " lib/ bin/` shows no caller-variable `eval`.
- [ ] `ENRICH_MISSING` defaults to false; `--enrich` opt-in documented + tested.
- [ ] Bootstrap engages `set -euo pipefail` + ERR trap before arg parsing
      (verified by a fault-injection test).

**Risks:** Strict-mode engagement (BASH-001) can expose latent `|| true`-masked
failures - run the full suite and triage. Perf default flip (PERF-001) changes
output completeness - release-note it.

**Quality gate:** standardized gate; coverage must increase, not regress; every
recent defect has a dedicated regression test.

**Expected artifacts:** new/updated BATS files, hardened library + scripts,
bootstrap refactor, perf cache, CHANGELOG/release notes, version bump, atomic
commit(s) (one per logical group if split into M4a/M4b).

---

### M5 - Documentation & Polish (target: 2-3 days)

**Goal:** Eliminate documentation drift, finalize the CHANGELOG backfill (D-4),
fix the remaining portability/cleanup items, and prepare release artifacts for
the v1.0.0 tag.

**Findings addressed**

<!-- markdownlint-disable MD013 MD060 -->
| ID | Title | Effort | Cluster |
|----|-------|--------|---------|
| DOC-005 | `--remove` documented but command is `--uninstall` | S | - |
| DOC-002 | README test counts contradictory | S | - |
| DOC-003 | Script count "16+" vs actual 30 | S | - |
| DOC-004 | Script header version frozen; installer split identity | S | I |
| DOC-006 | Options table omits prepare/install/uninstall | S | - |
| DOC-007 | CONNECTOR_BASE auto-discovery not documented | S | - |
| DOC-008 | Broken link to `v0.19.0.md` | S | - |
| DOC-009 | `etc/.env.example` referenced; file missing | S | J |
| DOC-010 | lib/README.md v4.0.0 framing, wrong LOC | S | I |
| DOC-011 | doc/testing.md version + conflicting counts | S | - |
| DOC-012 | tests/README.md version, incomplete table | S | - |
| DOC-013 | CHANGELOG missing v0.19.2-v0.19.4 (D-4 backfill) | S | I |
| DOC-014 | "new in v0.6.1" anachronistic annotation | S | - |
| DOC-015 | Install example implies single-step install | S | - |
| DOC-016 | No onboarding docs for `ds_connector_create.sh` | M | - |
| REL-004 | Script header versions frozen at v0.19.1 | S | I |
| REL-005 | Installer `SCRIPT_VERSION=v1.1.0` out of sync | S | I |
| REL-008 | Release workflow runs tests twice | S | - |
| REL-009 | Tarball timestamp breaks reproducibility | S | - |
| REL-011 | Missing git tags v0.19.2/v0.19.3 (historical) | S | - |
| REL-012 | `[Unreleased]` CHANGELOG always empty (D-4: drop) | S | I |
| ARCH-002 (=PERF-008) | Bootstrap version-grep copied 25x | M | H |
| ARCH-003 (=BASH-020) | `is_ocid` defined twice | S | H |
| ARCH-004 (=PERF-010) | Two identical mtime helpers | S | H |
| ARCH-006 | Config naming loader vs example mismatch | S | J |
| ARCH-010 | Version metadata drift | S | I |
| ARCH-012 | `ssh_helpers.sh` loaded for all, used by few | S | - |
| ARCH-013 | `oci_helpers.sh` owns Data Safe domain logic | L | - |
| DEP-003 | `grep -oP` breaks on BSD grep | S | - |
| DEP-008/009/010 | OCI CLI version, dep docs, `date +%s` | S | - |
| DEP-013 | `ds_database_prereqs.sh` duplicates logging | M | H |
| PERF-005/006/007/009/011 | subshell reduction in display/log paths | S-M | - |
| PERF-012 | Bulk ops serial, no bounded parallelism | L | - |
| ORA-010/011/012/016, ORA-008 | template + doc cleanups | S | - |
| BASH-005/009/018 | minor robustness/perf cleanups | S | - |
| TEST-016 | 3 permanently skipped tests | S | - |
<!-- markdownlint-enable MD013 MD060 -->

Effort sum: ~14 days raw across many S items; realistic 2-3 days for the
docs/version/CHANGELOG core, with PERF-012 and ARCH-013 (both L) explicitly
DEFERRED to v1.1 (flagged in Clarifications) so the v1.0.0 tag is not blocked on
them.

**Implementation tasks**

1. D-4: CHANGELOG without `[Unreleased]` - backfill 0.19.2/0.19.3/0.19.4 from the
   existing release-notes files; remove the empty `[Unreleased]` section
   (DOC-013, REL-012).
2. Single source of truth for version: Makefile updates script headers on bump;
   remove drift literals incl. installer `SCRIPT_VERSION=v1.1.0`, README
   v0.19.1, lib/README v4.0.0, stale annotations (REL-004, REL-005, ARCH-010,
   DOC-001/004/010/014, PERF-008 via `read -r SCRIPT_VERSION < VERSION`).
3. Fix factual doc errors: `--remove` -> `--uninstall`, test counts, script
   count, options table, broken link, `.env.example` -> `datasafe.conf.example`
   (DOC-002/003/005/006/007/008/009/011/012/015).
4. Config naming: one canonical filename aligned across loader/example/docs
   (ARCH-006, closes Cluster J with M2's SEC-005).
5. Dedup: delete duplicate `is_ocid`, duplicate mtime helper, duplicated logging
   (ARCH-003, ARCH-004, DEP-013); extract the shared bootstrap version-grep
   (ARCH-002).
6. Portability/cleanup: `grep -oP` -> `grep -oE` (DEP-003); BASH-005/009/018;
   subshell reduction PERF-005/006/007/009/011; SQL/template cleanups ORA-010/
   011/012; implement or remove the 3 skipped tests (TEST-016).
7. Release hygiene: drop redundant `make test` in release.yml (REL-008); pin
   tarball timestamp for reproducibility (REL-009); document missing historical
   tags (REL-011).
8. Onboarding doc for `ds_connector_create.sh` (DOC-016).

**Dependencies:** M1-M4 complete - docs must describe the final post-hardening
behaviour (uninstall flag, config name, enrich default, bash 4+ requirement,
macOS support).

**Acceptance criteria (measurable)**

- [ ] CHANGELOG has 0.19.2/0.19.3/0.19.4 entries and no `[Unreleased]` section.
- [ ] `grep -R "\-\-remove" doc/ README.md` == 0; `--uninstall` documented.
- [ ] `grep -R "v0.19.1\|v1.1.0\|v4.0.0" doc/ lib/README.md bin/` == 0 for stale
      version strings.
- [ ] `markdownlint` clean across all touched docs.
- [ ] `grep -R "grep -oP" bin/ lib/` == 0.
- [ ] One authoritative test count, consistent across README/doc/testing.md/
      tests/README.md.
- [ ] PERF-012 and ARCH-013 explicitly recorded as v1.1 deferrals in
      Clarifications, not silently dropped.

**Risks:** Low. Main risk is documentation describing behaviour that M2-M4
changed - mitigated by ordering M5 last.

**Quality gate:** standardized gate; markdownlint clean is the dominant check;
this is the last milestone before the v1.0.0 readiness gate.

**Expected artifacts:** updated CHANGELOG, release notes, README, doc/ tree,
lib/README, config example rename, deduped library, cleanup commits, version
bump, atomic commit(s).

---

## Quality Gates

### Standardized per-milestone gate

Every milestone closes only when ALL of the following pass (this is the
done-signal the driver loop checks, in addition to artifact existence):

1. Build OK - `make build` produces the tarball without error.
2. Framework validation - `make check-version` passes; `make info` consistent.
3. ShellCheck clean - `make lint-shell` with `--shell=bash`, zero warnings.
4. `shfmt -d` clean - `make format-check` reports no diff.
5. Unit tests - `make test` green (now actually fails on red, post-M1).
6. Integration tests - `make test-all` green where OCI config is available;
   guarded/skipped consistently otherwise (TEST-014).
7. Regression tests - every recent defect maps to a dedicated test; the
   REG-001..REG-012 set defined in `doc/review/findings/testing.md` is green for
   the milestones that own them (M3 requires REG-001..006; M4 owns the full set).
8. Docs updated - relevant `doc/` and README sections reflect the change.
9. CHANGELOG updated - entry written at release time, no `[Unreleased]` (D-4).
10. Release notes updated - matching `doc/releasenotes/` (or equivalent) entry.
11. Version bump where applicable - `VERSION` and `.extension` in sync.
12. One atomic Git commit per logical unit with a Conventional Commit message
    (`type(scope): description`), no `Co-Authored-By`.

`make ci` (clean lint test build) is the single command that exercises gates
1-6 locally and in CI.

### v1.0.0 tag gate

In addition to the standardized gate on M5, the v1.0.0 tag requires the
`doc/milestone-v1.0.0.md` checklist (authored in M1) to pass - see Release
Strategy.

---

## Automation Design

The repository ships no `.claude/agents/`; the available agents are the global
`architect` and `reviewer` at `/Users/stefan.oehrli/.claude/agents/`. The
roadmap is automation-friendly with this mapping (create repo-local
`.claude/agents/*` symlinks or definitions as the orchestrator requires; named
roles below are the intended executors).

<!-- markdownlint-disable MD013 MD060 -->
| Milestone | Primary agent role | Done-signal the driver checks |
|-----------|--------------------|-------------------------------|
| M1 | `release-eng` (Makefile/CI) + `security` (password) | `doc/milestone-v1.0.0.md` exists AND a planted failing test turns `make ci` red AND `grep DS_Admin.2025` == 0 |
| M2 | `security` + `oracle` | Credential-path regression tests green AND argv/`/tmp` greps clean AND standardized gate pass |
| M3 | `architect` (installer) + `reviewer` | REG-001..006 green on Linux AND macOS AND no hardcoded path outside resolver AND gate pass |
| M4 | `test-qa` + `bash-robustness` | REG-001..012 present+green AND TEST-012 sites == 0 AND gate pass |
| M5 | `docs` + `reviewer` | markdownlint clean AND stale-version greps clean AND CHANGELOG backfilled AND gate pass |
<!-- markdownlint-enable MD013 MD060 -->

Driver/loop contract per milestone:

- Done-signal = artifact existence (files in the "Expected artifacts" list) AND a
  green standardized quality gate (`make ci` exit 0 plus the milestone-specific
  greps/tests above). The loop does not advance on artifact presence alone.
- On gate failure, the loop re-plans within the milestone (does not push forward,
  per the project re-plan rule) and retries; it never force-pushes and never
  resets `--hard`.

Human approval is required ONLY at these predefined decision gates:

1. Before M1 commit lands on `main` (the gate change is repo-wide).
2. Before the v1.0.0 tag (final readiness sign-off).
3. If any milestone surfaces a finding requiring a scope change beyond D-1..D-5
   (e.g., M4 splitting into M4a/M4b, or promoting a deferred v1.1 item).

All other steps run autonomously.

---

## Release Strategy

Interim tags after each hardening milestone give bisectable, releasable
checkpoints; v1.0.0 follows a clean run of the readiness gate after M5.

<!-- markdownlint-disable MD013 MD060 -->
| Phase | Version | Trigger | Notes |
|-------|---------|---------|-------|
| M1 close | v0.21.0 | Release gate live + blockers ORA-001/REL-* cleared | First release that CI can actually block |
| M2 close | v0.22.0 | Security hardening complete | Credential + IAM + Oracle posture fixed |
| M3 close | v0.23.0 | Installer hardened (Linux + macOS) | Defect engine closed; standalone per D-1 |
| M4 close | v0.24.0 | Regression + robustness + perf complete | All recent defects have regression tests |
| Stabilization | v0.25.0-rc.1 | M5 docs/polish complete | Release candidate; soak/integration validation |
| RC validation | v0.25.0-rc.N | Gate failures fixed | Additional RCs only if the gate goes red |
| GA | v1.0.0 | Readiness checklist passes | Single tag from `main` after a clean `make ci` |
<!-- markdownlint-enable MD013 MD060 -->

Version numbers above are placeholders for sequencing; the actual bumps are
driven by `make version-bump-*` and the SemVer impact of each milestone (M3/M4
default flips such as `ENRICH_MISSING=false` and the bash 4+ requirement are
minor-version, behaviour-changing - documented in release notes). Dates are
intentionally omitted (no fabricated dates).

### v1.0.0 readiness checklist

The v1.0.0 tag is created only when all of the following hold (this is the body
of `doc/milestone-v1.0.0.md`, authored in M1):

- [ ] `make ci` exits 0 on a clean checkout (clean lint test build).
- [ ] ShellCheck `--shell=bash`: zero warnings across `bin/` and `lib/`.
- [ ] `make format-check` (`shfmt -d`): no diff.
- [ ] All BATS tests green; no `status 0 or 1` zero-signal assertions remain.
- [ ] REG-001..REG-012 present and green.
- [ ] All nine risk-register blockers closed (REL-001, ORA-001, TEST-002,
      TEST-003, ARCH-007, REL-007, REL-006, SEC-002, SEC-004).
- [ ] No secret on argv or at a predictable plaintext path (audited).
- [ ] Installer `--prepare`/`--install --dry-run` pass on Linux AND macOS.
- [ ] bash 4.0+ guard active; requirement documented.
- [ ] CHANGELOG complete (0.19.2..current), no `[Unreleased]` section.
- [ ] README/docs version strings derived from `VERSION`; no stale literals.
- [ ] `VERSION` and `.extension` in sync.
- [ ] v1.1 deferrals (PERF-012, ARCH-013) recorded in Clarifications.
- [ ] Human sign-off recorded (decision gate 2).

---

## Clarifications

All D-1 through D-5 decisions are resolved. The following clarifications
(C-1 through C-3, plus residual items) are now also resolved:

<!-- markdownlint-disable MD013 MD060 -->
| Clarification | Decision | Impact |
|---|---|---|
| C-1 ORA-001 password purge | Remove from code in M1 (default to `''`, fail on empty). NO git history rewrite. | M1 scope unchanged; history stays as-is |
| C-2 Interim releases | YES - tag after each milestone: v0.21.0 (M1) .. v0.25.0-rc + v1.0.0 | Release strategy confirmed as documented |
| C-3 PERF-012 + ARCH-013 | INCLUDED in v1.0 - PERF-012 in M4, ARCH-013 in M5. No v1.1 deferral. | M4 effort +L; M5 effort +L - both realistic within the milestone windows |
| Release notes path | `doc/release_notes/` (confirmed from repo, not `doc/releasenotes/`) | CHANGELOG backfill references correct path |
| Repo-local agents | Global `architect`/`reviewer` plus role prompts are sufficient | No repo-local `.claude/agents/` required |
<!-- markdownlint-enable MD013 MD060 -->

No open items remain. Implementation may begin with M1.
