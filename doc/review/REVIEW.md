# Framework Review - odb_datasafe v0.20.4 -> v1.0.0

<!-- markdownlint-disable MD013 MD060 -->
| Field | Value |
|---|---|
| Date | 2026-06-28 |
| Reviewer | Claude Code (framework-review) |
| Base version | v0.20.4 |
| Target version | v1.0.0 |
| Review type | oracle-scripts (bash-framework + SQL/audit) |
| Scope | full |
<!-- markdownlint-enable MD013 MD060 -->

---

## Executive Summary

`odb_datasafe` is a Bash extension for managing Oracle OCI Data Safe targets and
connectors. It provides 30 entry-point scripts backed by five shared libraries
(~16,500 LOC total), covering target registration, connector lifecycle, database
privilege provisioning, and systemd service installation. The project follows the
OraDBA script conventions and targets OCI CLI as its primary API surface.

The overall quality posture is uneven. The library layer and core target-management
scripts are structurally sound, but the installer (`bin/install_datasafe_service.sh`,
1,372 LOC) has been the recurring defect engine - three patches shipped in a single
day (v0.20.2, v0.20.3, v0.20.4) all targeting the same installer functions. The
fundamental cause is that the installer hardcodes Oracle and systemd paths, validates
too late, and lacks an ERR/EXIT trap. This problem will recur until the layout
discovery and validation sequence are fixed.

The single most critical finding is REL-001: `make test` swallows the bats exit code
and the CI workflow sets `continue-on-error: true`. As a result, no test failure has
ever blocked a PR or release tag. This means every other quality claim in the
repository - "227+ BATS tests", ShellCheck compliance, format checks - is
unverifiable. The second most critical finding is ORA-001: the default admin
password `DS_Admin.2025` is committed in SQL templates and visible in the public
repository. Both are S-effort (hours) fixes and must land before any other
improvement carries meaning.

The review identified 112 distinct findings (127 raw, 15 deduplicated) across 9
domains. Nine score as v1.0.0 blockers. The roadmap sequences these into five
milestones (M1-M5, estimated 16-26 working days) with interim tags after each.
v1.0.0 is achievable and the codebase does not require a rewrite - but the CI gate
must be restored first.

---

## Repository Snapshot

<!-- markdownlint-disable MD013 MD060 -->
| Metric | Value |
|---|---|
| Version | 0.20.4 |
| Total LOC (executable) | ~16,500 |
| `bin/` scripts | 30 |
| `lib/` modules | 5 |
| SQL scripts | 6 |
| BATS test files | 32 |
| BATS `@test` blocks | 319 |
| Key dependencies | bash 4.0+, OCI CLI, jq, sqlplus (optional), bats-core |
| Latest commit | 2026-06-25 (v0.20.4) |
| CI workflows | 1 (`.github/workflows/`) |
<!-- markdownlint-enable MD013 MD060 -->

---

## Finding Counts

<!-- markdownlint-disable MD013 MD060 -->
| Domain | Critical | High | Medium | Low | Total |
|--------|----------|------|--------|-----|-------|
| Architecture (ARCH) | 0 | 3 | 4 | 6 | 13 |
| Security (SEC) | 0 | 2 | 5 | 3 | 10 |
| Oracle (ORA) | 1 | 3 | 6 | 6 | 16 |
| Release (REL) | 2 | 5 | 1 | 4 | 12 |
| Testing (TEST) | 3 | 9 | 3 | 1 | 16 |
| Bash (BASH) | 0 | 3 | 10 | 6 | 19 |
| Dependencies (DEP) | 0 | 3 | 6 | 4 | 13 |
| Documentation (DOC) | 0 | 4 | 8 | 4 | 16 |
| Performance (PERF) | 1 | 3 | 5 | 3 | 12 |
| **Raw total (pre-dedup)** | **7** | **35** | **48** | **37** | **127** |
| **Distinct (post-dedup)** | **5** | **~31** | **~41** | **~35** | **~112** |
<!-- markdownlint-enable MD013 MD060 -->

After deduplication across domains (15 duplicate IDs folded into 11 canonical
findings), the effective distinct finding count is approximately 112. Severity is
taken as the highest reported across contributing domains.

---

## Top-20 Findings

Priority score = impact x (1/effort) x blast_radius, normalized to 1-100.
Security findings multiplied by 1.5; installer/deployment defects multiplied by
1.5 on blast-radius (affects all users).

<!-- markdownlint-disable MD013 MD060 -->
| Rank | ID | Severity | Domain | One-line title | Effort | Score | Milestone |
|------|----|----------|--------|----------------|--------|-------|-----------|
| 1 | REL-001 | Critical | Release | `make test` masks bats exit code; CI cannot fail (incl. TEST-001, REL-002) | S | 100 | M1 |
| 2 | ORA-001 | Critical | Oracle | Hardcoded default password `DS_Admin.2025` in SQL (incl. SEC-001) | S | 99 | M1 |
| 3 | REL-007 | High | Release | `make release` bumps version without lint/test gate | S | 92 | M1 |
| 4 | DEP-001 | High | Deps | No bash 4.0+ runtime guard; macOS ships 3.2 (incl. DEP-011, BASH-021) | S | 88 | M1 |
| 5 | SEC-002 | High | Security | DB secret on command line, visible in `ps` (incl. ORA-002) | S | 86 | M2 |
| 6 | ARCH-007 | High | Arch | Hardcoded Oracle/systemd paths - root cause of v0.20.2-v0.20.4 defects (incl. DEP-002, DEP-007) | L | 85 | M3 |
| 7 | SEC-004 | Medium | Security | Register payload predictable /tmp path, plaintext, no trap (incl. BASH-015) | S | 84 | M2 |
| 8 | TEST-002 | Critical | Testing | `find_connector_base()` - the v0.20.4 fix has no test | M | 83 | M1 |
| 9 | TEST-003 | Critical | Testing | User= mismatch auto-regeneration has no regression test | M | 82 | M1 |
| 10 | ORA-013 | High | Oracle | `manage data-safe-family in tenancy` over-broad IAM grant | S | 80 | M2 |
| 11 | ARCH-001 | High | Arch | Installer is 1372-LOC god script bypassing framework (incl. BASH-016, BASH-006) | XL | 78 | M3 |
| 12 | SEC-005 | Medium | Security | Config files sourced without ownership/permission checks | M | 76 | M2 |
| 13 | ORA-003 | High | Oracle | `PASSWORD_LOCK_TIME` 5 min vs CIS 1 day | S | 74 | M2 |
| 14 | TEST-007 | High | Testing | `oci_exec` stderr isolation - shipped defect has no regression (incl. ARCH-005, BASH-014, SEC-010) | M | 73 | M1 |
| 15 | BASH-001 | High | Bash | `setup_error_handling` deferred; bootstrap unprotected (incl. ARCH-009, BASH-003) | M | 72 | M4 |
| 16 | BASH-002 | High | Bash | 2 scripts have zero error protection (incl. SEC-009) | S | 71 | M1 |
| 17 | PERF-001 | Critical | Perf | Default-on per-target OCI GET enrichment, O(N) serial | S | 70 | M4 |
| 18 | REL-003 | High | Release | shfmt format-check absent from CI | S | 68 | M1 |
| 19 | DEP-012 | Medium | Deps | Vendor `setup.py` executed without checksum verification (incl. DEP-004) | M | 66 | M2 |
| 20 | DOC-005 | High | Docs | `--remove` flag documented but does not exist (`--uninstall`) | S | 64 | M5 |
<!-- markdownlint-enable MD013 MD060 -->

---

## Cross-Domain Clusters

Eleven root-cause clusters span multiple domains. Fixing the canonical finding
closes all member findings together.

- **Cluster A** - CI/release gate non-functional. Root cause: `Makefile:127-129`
  swallows bats exit codes; `ci.yml:65` sets `continue-on-error: true`. Canonical:
  REL-001.
- **Cluster B** - Hardcoded/process-visible credentials. Root cause: secrets handled
  as literals/argv rather than via `file://` + `mktemp` + `umask 077`. Canonical:
  ORA-001 (hardcoded), SEC-002 (argv).
- **Cluster C** - Installer god script and hardcoded layout (recurring defect engine).
  Root cause: 1,372-LOC `install_datasafe_service.sh` reimplements the framework,
  hardcodes layout, and validates too late. Canonical: ARCH-001 / ARCH-007.
- **Cluster D** - No bash version guard (portability). Root cause: bash 4.0+ features
  used throughout with no `BASH_VERSINFO` check; macOS ships 3.2. Canonical: DEP-001.
- **Cluster E** - Strict-mode not actually engaged. Root cause: `AUTO_ERROR_HANDLING=false`
  default and per-script opt-in placed inside `main()` after config parsing. Canonical:
  BASH-001.
- **Cluster F** - `eval` to set caller variables. Root cause: `resolve_*_to_vars`
  builds `eval "${prefix}_OCID=..."` with OCI API values. Canonical: ARCH-011.
- **Cluster G** - `oci_exec` bypass and stderr contamination. Root cause:
  `ds_refresh_target` uses `oci ... 2>&1` instead of the `oci_exec` wrapper,
  reintroducing a defect fixed in `c74c7ad`. Canonical: TEST-007.
- **Cluster H** - Duplicated definitions. Root cause: `is_ocid`, `_ds_cache_mtime`,
  version-grep boilerplate, and logging duplicated across files. Canonical:
  ARCH-003 / ARCH-004 / ARCH-002.
- **Cluster I** - Version metadata drift. Root cause: script headers frozen at
  v0.19.1, fallback literals drift independently, installer hardcodes
  `SCRIPT_VERSION=v1.1.0`. Canonical: ARCH-010.
- **Cluster J** - Config-file naming and discovery mismatch. Root cause: loader
  expects `datasafe.conf`, repo ships `odb_datasafe.conf.example`; docs reference
  `etc/.env.example` (nonexistent). Canonical: ARCH-006.
- **Cluster K** - Query/filter string injection. Root cause: user-influenced values
  interpolated into OCI `--query`, jq filter, and SQL strings instead of using
  `--arg` / identifier whitelisting. Canonical: BASH-007 / BASH-008.

---

## v1.0.0 Blockers

All nine findings below score Risk Score 9 (Likelihood High x Impact High). All
are open at the time of this review.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Finding | Risk Score | Status |
|----|---------|-----------|--------|
| REL-001 | `make test`/CI mask bats exit code - tests can never fail a PR or release | 9 | Open |
| ORA-001 | Hardcoded `DS_Admin.2025` admin password in committed SQL | 9 | Open |
| TEST-002 | `find_connector_base()` (the v0.20.4 fix) has no regression test | 9 | Open |
| TEST-003 | User= mismatch auto-regeneration has no regression test | 9 | Open |
| ARCH-007 | Hardcoded Oracle/systemd paths - active source of v0.20.2-v0.20.4 defects | 9 | Open |
| REL-007 | `make release` bumps version without lint/test gate | 9 | Open |
| REL-006 | Same-day patch cadence - no pre-release validation gate | 9 | Open |
| SEC-002 | DB secret on command line, visible via `ps`/history | 9 | Open |
| SEC-004 | Register payload at predictable /tmp path, plaintext secret, no EXIT trap | 9 | Open |
<!-- markdownlint-enable MD013 MD060 -->

---

## Decisions Recorded

All ten decisions are resolved and baked into the milestone scope below.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Question | Decision |
|----|---------|---------|
| D-1 | Full refactor of installer to source framework, or targeted hardening standalone? | Installer stays standalone permanently. Harden in place: regression tests, ERR/EXIT traps, centralized layout discovery. Full framework integration deferred to v1.1. |
| D-2 | Support bash 3.x (macOS default) or require 4.0+ with a hard guard? | Require bash 4.0+. Add `BASH_VERSINFO` guard in `lib/common.sh` at source time; document that macOS users install bash 4+ via Homebrew. |
| D-3 | Keep `--grant-mode ALL` default or switch to least-privilege subset? | `--grant-mode ALL` STAYS default. Document the full privilege surface in the prerequisites doc. ORA-006/ORA-007 reduced to documentation tasks. |
| D-4 | Adopt Keep-a-Changelog `[Unreleased]` accumulation, or entries at release time? | NO `[Unreleased]` section. Entries written at release time. Backfill 0.19.2/0.19.3/0.19.4 from existing release notes. |
| D-5 | Is the installer expected to run on macOS? | Installer supports Linux AND macOS. `uname -s` OS detection plus per-command `command -v` checks; clear error when a required command is absent on the current OS. |
| C-1 | How to handle the `DS_Admin.2025` credential purge? | Remove from code in M1 (default to `''`, fail on empty). NO git history rewrite. |
| C-2 | Ship interim releases between milestones? | YES - tag after each milestone: v0.21.0 (M1) through v0.25.0-rc + v1.0.0. |
| C-3 | Defer PERF-012 and ARCH-013 to v1.1? | INCLUDED in v1.0.0 - PERF-012 in M4, ARCH-013 in M5. No deferral. |
| C-4 | Release notes path? | `doc/release_notes/` (confirmed from repo). CHANGELOG backfill references correct path. |
| C-5 | Repo-local Claude agents required? | Global `architect`/`reviewer` plus role prompts are sufficient. No repo-local `.claude/agents/` required. |
<!-- markdownlint-enable MD013 MD060 -->

---

## Roadmap Summary

Five milestones take the project from v0.20.4 to v1.0.0. Each produces an interim
release tag. Effort estimates are realistic (not optimistic); raw totals are higher
but most S items cluster around adjacent files.

<!-- markdownlint-disable MD013 MD060 -->
| Milestone | Goal | Version | Effort | Finding count |
|-----------|------|---------|--------|--------------|
| M1 - Release Gate Restoration | Restore working CI/release gate; close credential and release blockers | v0.21.0 | ~2 days | 9 findings |
| M2 - Security Hardening | Eliminate credential exposure; reduce IAM/Oracle privilege surface | v0.22.0 | 3-5 days | 17 findings |
| M3 - Installer Hardening | Centralize layout discovery; ERR/EXIT traps; Linux + macOS support | v0.23.0 | 5-8 days | 8 findings |
| M4 - Test Coverage & Robustness | Regression tests for all recent defects; strict mode; perf defaults | v0.24.0 | 5-8 days | 31 findings |
| M5 - Documentation & Polish | CHANGELOG backfill; version drift; doc accuracy; dedup; cleanup | v1.0.0 | 2-3 days | 40+ findings |
<!-- markdownlint-enable MD013 MD060 -->

### v1.0.0 Readiness Checklist

The v1.0.0 tag is created only when all of the following hold:

- [ ] `make ci` exits 0 on a clean checkout (clean lint test build)
- [ ] ShellCheck `--shell=bash`: zero warnings across `bin/` and `lib/`
- [ ] `make format-check` (`shfmt -d`): no diff
- [ ] All BATS tests green; no `status 0 or 1` zero-signal assertions remain
- [ ] REG-001..REG-012 present and green
- [ ] All nine risk-register blockers closed (REL-001, ORA-001, TEST-002, TEST-003,
      ARCH-007, REL-007, REL-006, SEC-002, SEC-004)
- [ ] No secret on argv or at a predictable plaintext path (audited)
- [ ] Installer `--prepare`/`--install --dry-run` pass on Linux AND macOS
- [ ] bash 4.0+ guard active; requirement documented
- [ ] CHANGELOG complete (0.19.2..current), no `[Unreleased]` section
- [ ] README/docs version strings derived from `VERSION`; no stale literals
- [ ] `VERSION` and `.extension` in sync
- [ ] v1.1 deferrals recorded in Clarifications (none remaining per C-3)
- [ ] Human sign-off recorded (decision gate 2)

---

## Quick Wins

Thirteen items fixable in under 2 hours, standalone, low risk. Addressing these
first creates immediate visible improvement before the structured milestones land.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Fix | Why now |
|----|-----|---------|
| REL-001 / REL-002 | Remove `\|\| echo`, add `exit $$rc`, drop `continue-on-error` | Unblocks every other gate; one-line edits |
| ORA-001 / SEC-001 | Default password to `''`, fail on empty | Removes a public credential |
| REL-007 | `release: check version-bump-patch tag` | Stops releasing untested code |
| DEP-001 | Add `BASH_VERSINFO` guard in `lib/common.sh` | Closes the whole portability cluster |
| DOC-005 | s/`--remove`/`--uninstall`/ in two docs | Documented command currently errors out |
| DOC-001 | README/index "Latest Release" -> v0.20.4 | Visible inaccuracy |
| ORA-013 | Remove bare `... in tenancy` manage statements | Over-broad IAM, fix matches existing JSON example |
| BASH-008 | jq `--arg` in 2 spots in `ds_target_register` | Correctness + injection, isolated |
| DEP-003 | `grep -oP` -> `grep -oE` | Violates project rule, breaks on macOS |
| ARCH-003 / BASH-020 | Delete duplicate `is_ocid` | Trivial, removes divergence trap |
| ARCH-004 / PERF-010 | Delete `_ds_cache_mtime`, repoint caller | Trivial dedup |
| PERF-008 | `read -r SCRIPT_VERSION < VERSION` | Removes 3 forks per invocation, 21 scripts |
| REL-008 | Drop redundant standalone `make test` in `release.yml` | Saves ~30 min runner time |
<!-- markdownlint-enable MD013 MD060 -->

---

## Supporting Artifacts

All files are under `doc/review/` in the repository root.

### Phase 1 - Scans (raw evidence, no analysis)

- `doc/review/_scans/repo-structure.md` - Full directory tree, LOC counts, file
  inventory, entry points, version markers, git log summary
- `doc/review/_scans/static-findings.md` - ShellCheck and shfmt output; risky
  construct grep results; naming inconsistency evidence
- `doc/review/_scans/markdown-scan.md` - markdownlint violations by rule across
  all `.md` files with file:line evidence
- `doc/review/_scans/secrets-scan.md` - Grep results for credentials, OCIDs,
  private IPs, and sensitive patterns across the full repo
- `doc/review/_scans/test-coverage.md` - BATS test inventory (32 files, 319
  `@test` blocks), file-by-line breakdown, coverage gap map

### Phase 2 - Domain Findings (per-domain analysis)

- `doc/review/findings/architecture.md` - Module boundaries, coupling, duplication,
  abstraction quality, 13 findings (ARCH-001..ARCH-013)
- `doc/review/findings/security.md` - Credential exposure, privilege handling,
  filesystem safety, injection surface, 10 findings (SEC-001..SEC-010)
- `doc/review/findings/oracle.md` - SQL correctness, audit policy completeness,
  CIS/STIG alignment, privilege grants, 16 findings (ORA-001..ORA-016)
- `doc/review/findings/release.md` - Versioning, CI, CHANGELOG, release process
  maturity, 12 findings (REL-001..REL-012)
- `doc/review/findings/testing.md` - BATS coverage gaps, regression tests required
  for recent defects, 16 findings (TEST-001..TEST-016) + REG-001..REG-012 table
- `doc/review/findings/bash.md` - ShellCheck findings, `set -euo pipefail`
  correctness, quoting, error handling, 19 findings (BASH-001..BASH-024)
- `doc/review/findings/deps.md` - External command runtime validation, version
  assumptions, 13 findings (DEP-001..DEP-013)
- `doc/review/findings/docs.md` - README accuracy, CLI docs, CHANGELOG hygiene,
  16 findings (DOC-001..DOC-016)
- `doc/review/findings/performance.md` - Subprocess cost, OCI call patterns, cache
  opportunities, 12 findings (PERF-001..PERF-012)

### Phase 3 - Synthesis

- `doc/review/consolidated-findings.md` - Top-20 prioritized findings, 11
  cross-domain clusters, DECISION-REQUIRED items, quick-wins table
- `doc/review/technical-debt-register.md` - One row per canonical finding with
  severity, domain, debt type, effort, and milestone assignment
- `doc/review/risk-register.md` - Critical and High findings with Likelihood x
  Impact risk scores; nine v1.0.0 blockers identified

### Phase 4 - Roadmap

- `doc/review/roadmap.md` - Five milestones (M1-M5) with implementation tasks,
  acceptance criteria, quality gates, automation design, and release strategy;
  all decisions D-1..D-5 and C-1..C-5 resolved and baked in

### Phase 5 - Assembly

- `doc/review/REVIEW.md` - This file; standalone permanent record of the review
- `doc/review/_params.md` - Review parameters and scope definition
- `doc/review/clarifications.md` - Resolved clarifications (C-1..C-5) and
  decision log
