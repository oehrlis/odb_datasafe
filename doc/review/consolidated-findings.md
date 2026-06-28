# Consolidated Findings - odb_datasafe v0.20.4 -> v1.0.0

Synthesis of 9 domain reviews (architecture, security, oracle, release, testing,
bash, deps, docs, performance). Findings are deduplicated against a canonical ID;
cross-domain duplicates are noted in parentheses and not double-counted.

## Summary - finding counts by severity

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
| Raw total (pre-dedup) | 7 | 35 | 48 | 37 | 127 |
<!-- markdownlint-enable MD013 MD060 -->

After deduplication across domains (15 duplicate IDs folded into 11 canonical
findings), the effective distinct finding count is approximately 112. Severity is
taken as the highest reported across contributing domains.

Effort legend: S = hours (<=4h), M = days (1-2d), L = ~1 week, XL = >1 week or
multi-subsystem refactor.

Milestone legend: M1 = release-gate blockers (must fix before any new tag),
M2 = security hardening, M3 = installer/architecture refactor, M4 = test coverage
and robustness, M5 = docs, performance polish, cleanup.

---

## 1. Top-20 prioritized findings

Priority score = impact x (1/effort) x blast_radius, normalized to 1-100.
Security multiplied by 1.5 (Oracle/OCI infra at risk); installer/deployment defects
multiplied by 1.5 on blast-radius (affects all users); missing tests for known
defect classes ranked High.

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

## 2. Cross-domain clusters

Findings from different domains that share a single root cause. Fix the cluster
once; all member findings close together.

### Cluster A - CI/release has no working quality gate

- Members: REL-001, REL-002, TEST-001 (all the same exit-code defect), REL-007,
  REL-003, REL-006, REL-010.
- Root cause: `Makefile:127-129` swallows bats exit codes and `ci.yml:65` sets
  `continue-on-error: true`; `make release` has no `check` prerequisite.
- Effect: broken tests and lint failures can never block a PR or a tag. This is why
  five same-day patches (v0.20.2-v0.20.4) shipped regressions.
- Fix order: REL-001 + REL-002 first (S), then REL-007 + REL-003 (S), then REL-010
  (the v1.0.0 readiness checklist) ties it together.

### Cluster B - Hardcoded / process-visible credentials

- Members: ORA-001 = SEC-001 (hardcoded password, canonical ORA-001), SEC-002 =
  ORA-002 (secret on argv), SEC-003 (bundle password on argv), SEC-004 = BASH-015
  (predictable temp credential file), SEC-010 (incomplete log redaction).
- Root cause: secrets handled as literals/argv rather than via files + mktemp +
  restrictive umask. A safe pattern already exists in
  `ds_target_update_credentials.sh` (`--credentials file://<mktemp>`).
- Fix: rotate `DS_Admin.2025`, make SQL fail on empty password, move all secrets to
  `file://` + `mktemp` + `umask 077` + EXIT trap, broaden `_oci_redact_cmd`.

### Cluster C - Installer god script and hardcoded layout (defect engine)

- Members: ARCH-001 (god script), ARCH-007 (hardcoded paths), ARCH-008 (leaky
  prepare/install contract), BASH-006 (stdout routing), BASH-016 (no ERR/EXIT trap),
  BASH-023 = SEC-006 (broad chown, masked), DEP-002 (`systemctl`/`visudo`/`getent`
  unchecked), DEP-007 (broken unit on missing `oradba_dsctl.sh`), SEC-007 (sudoers
  wildcard), TEST-002, TEST-003, TEST-004, TEST-005, TEST-006 (no installer tests).
- Root cause: `bin/install_datasafe_service.sh` (1372 LOC) reimplements the
  framework and hardcodes layout, validating too late. Every recent regression lives
  here. See DECISION-REQUIRED D-1 for refactor scope.
- Fix: centralize layout discovery, resolve binaries via `command -v`, move
  validation into `--prepare`, add the 5 missing regression tests first (M1) so the
  refactor (M3) is safe.

### Cluster D - No bash version guard (portability)

- Members: DEP-001 (canonical), DEP-011, BASH-021 (all `mapfile`/bash-4 usage),
  plus `${var^^}`/`declare -A` usage in DEP-013.
- Root cause: bash 4.0+ features used throughout, no `BASH_VERSINFO` check; macOS
  ships bash 3.2. See DECISION-REQUIRED D-2 (support 3.x or guard-and-require 4.0).
- Fix: single guard in `lib/common.sh` at source time resolves all members.

### Cluster E - Strict-mode / error-handling not actually engaged

- Members: ARCH-009 (ERR trap opt-in/dormant), BASH-001 (deferred
  `setup_error_handling`), BASH-002 (2 scripts no protection), BASH-003 (libs sourced
  without `set -e`), SEC-009 (widespread `|| true` + missing `set -euo pipefail`).
- Root cause: `AUTO_ERROR_HANDLING=false` default + per-script opt-in placed inside
  `main()` after config/arg parsing.
- Fix: enable strict mode + ERR trap in the shared bootstrap (depends on ARCH-002).

### Cluster F - eval to set caller variables

- Members: ARCH-011 (canonical) = BASH-019.
- Root cause: `resolve_*_to_vars` build `eval "${prefix}_OCID=..."` with OCI API
  values. Contradicts the documented "no eval" posture.
- Fix: `printf -v "${prefix}_OCID" '%s' "$input"`.

### Cluster G - `oci_exec` bypass and stderr contamination

- Members: TEST-007 (canonical - no regression for shipped defect), ARCH-005,
  BASH-014, SEC-010 (raw `2>&1` written to log).
- Root cause: `ds_refresh_target` uses `oci ... 2>&1` instead of the `oci_exec`
  wrapper, reintroducing the FutureWarning-on-stdout bug that commit `c74c7ad` fixed.
- Fix: route `ds_refresh_target` through `oci_exec`; add REG-007 regression test.

### Cluster H - Duplicated definitions

- Members: ARCH-003 = BASH-020 (`is_ocid` double-defined), ARCH-004 = PERF-010
  (`_ds_cache_mtime` vs `_ds_file_mtime`), DEP-013 (duplicated logging in
  `ds_database_prereqs.sh`), ARCH-002 = PERF-008 (bootstrap version-grep copied 25x).
- Fix: pick one home per function; extract shared bootstrap.

### Cluster I - Version metadata drift

- Members: ARCH-010 (canonical), REL-004, REL-005, DOC-004, DOC-001, DOC-013.
- Root cause: header `Version` lines frozen at v0.19.1, fallback literals drift,
  installer hardcodes `SCRIPT_VERSION=v1.1.0`, stale `v4.0.0` strings, README shows
  v0.19.1, CHANGELOG missing 0.19.2-0.19.4.
- Fix: single source of truth (`.extension`/VERSION); Makefile updates headers on
  bump; remove fallback literals.

### Cluster J - Config-file naming and discovery

- Members: ARCH-006 (canonical), DOC-009 (`etc/.env.example` does not exist),
  SEC-005 (config sourced unchecked).
- Root cause: loader expects `datasafe.conf`, repo ships `*.conf.example` /
  `odb_datasafe.conf.example`; docs reference a nonexistent `.env.example`.
- Fix: one canonical filename, align loader + example + docs, log which configs load,
  validate ownership before sourcing.

### Cluster K - Query/filter string injection (correctness + safety)

- Members: BASH-007 (OCI `--query` unsanitized compartment name), BASH-008 (jq
  filter embeds shell var), ORA-009 (HOST round-trip), ORA-015 (`--ds-user`/`--pdb`
  unquoted into SYSDBA SQL).
- Root cause: user-influenced values interpolated into query/filter/SQL strings
  instead of using `--arg` / identifier whitelisting (pattern already used elsewhere).
- Fix: `jq --arg`, JMESPath structured search, identifier regex validation.

---

## 3. DECISION-REQUIRED items

These need a human choice before implementation; the rest are resolved by repo
analysis.

### D-1 - Installer refactor scope (ARCH-001, Cluster C)

- Question: Full refactor of `install_datasafe_service.sh` to source the framework
  (`lib/common.sh`/`ds_lib.sh`), or targeted hardening that keeps the standalone
  script?
- Context: 1372 LOC, parallel logging/argparse, the active defect source. Full
  refactor is XL and high-risk near v1.0.0; targeted hardening is L but leaves two
  framework implementations.
- Options: (a) Full integration now (XL, M3) - cleanest, riskiest pre-1.0;
  (b) Add regression tests now (M1) + centralize layout discovery + ERR/EXIT traps
  only (L, M3), defer full integration to v1.1; (c) Leave standalone, document it.
- Default if no answer: (b) - tests first, then minimal hardening; defer full
  integration. Lowest risk to v1.0.0 while closing the defect engine.

### D-2 - bash 3.x support (DEP-001, Cluster D)

- Question: Support bash 3.2 (macOS default) or require 4.0+ with a hard guard?
- Context: 12+ `mapfile`/`declare -A`/`${var^^}` sites. Rewriting for 3.2 is L and
  ongoing tax; a guard is S.
- Options: (a) Require 4.0+, add guard, document (S); (b) Backport to 3.2 (L).
- Default if no answer: (a) - add guard, document "bash 4.0+ required". The tool
  targets Linux connector hosts where 4.x is standard.

### D-3 - `--grant-mode` default (ORA-006, ORA-007)

- Question: Keep `DS_GRANT_MODE=ALL` default or switch to a least-privilege subset?
- Context: ALL grants MASKING/DATA_DISCOVERY ANY-privileges on every registration.
  Changing the default is a behavior change for existing operators.
- Options: (a) Default to `ASSESSMENT,AUDIT_COLLECTION,AUDIT_SETTING`, require opt-in
  for the rest; (b) Keep ALL, document the privilege surface prominently.
- Default if no answer: (a) - least privilege by default; release-note the change.

### D-4 - `[Unreleased]` CHANGELOG workflow (REL-012, DOC-013)

- Question: Adopt Keep-a-Changelog `[Unreleased]` accumulation, or write entries at
  release time and drop the empty section?
- Context: Section is always empty; backfill of 0.19.2-0.19.4 needed regardless.
- Default if no answer: adopt `[Unreleased]` accumulation and backfill the missing
  versions from existing release notes.

### D-5 - macOS as supported platform for the installer (DEP-002)

- Question: Is `install_datasafe_service.sh` ever expected to run on macOS?
- Context: It uses `systemctl`, `visudo`, `getent` (none on macOS). If Linux-only,
  add an explicit `uname -s` guard rather than per-command checks.
- Default if no answer: Linux-only - add an OS guard with a clear error, document it.

---

## 4. Quick wins

High value, fixable in under ~2h, standalone, low risk.

<!-- markdownlint-disable MD013 MD060 -->
| ID | Fix | Why now |
|----|-----|---------|
| REL-001 / REL-002 | Remove `|| echo`, add `exit $$rc`, drop `continue-on-error` | Unblocks every other gate; one-line edits |
| ORA-001 / SEC-001 | Default password to `''`, fail on empty | Removes a public credential |
| REL-007 | `release: check version-bump-patch tag` | Stops releasing untested code |
| DEP-001 | Add `BASH_VERSINFO` guard in `lib/common.sh` | Closes the whole portability cluster |
| DOC-005 | s/`--remove`/`--uninstall`/ in two docs | Documented command currently errors out |
| DOC-001 | README/index "Latest Release" -> v0.20.4 | Visible inaccuracy |
| ORA-013 | Remove bare `... in tenancy` manage statements | Over-broad IAM, fix matches existing JSON example |
| BASH-008 | jq `--arg` in 2 spots in ds_target_register | Correctness + injection, isolated |
| DEP-003 | `grep -oP` -> `grep -oE` | Violates project rule, breaks on macOS |
| ARCH-003 / BASH-020 | Delete duplicate `is_ocid` | Trivial, removes divergence trap |
| ARCH-004 / PERF-010 | Delete `_ds_cache_mtime`, repoint caller | Trivial dedup |
| PERF-008 | `read -r SCRIPT_VERSION < VERSION` | Removes 3 forks per invocation, 21 scripts |
| REL-008 | Drop redundant standalone `make test` in release.yml | Saves ~30 min runner time |
<!-- markdownlint-enable MD013 MD060 -->

---

## Traceability note

Every ID above traces to one of the 9 files under
`/Users/stefan.oehrli/Repos/own/oehrlis/odb_datasafe/doc/review/findings/`.
Duplicate IDs folded into a canonical finding:
SEC-001 -> ORA-001; ORA-002 -> SEC-002; BASH-015 -> SEC-004; SEC-006 -> BASH-023;
DEP-011 + BASH-021 -> DEP-001; BASH-019 -> ARCH-011; BASH-020 -> ARCH-003;
PERF-010 -> ARCH-004; ARCH-005 + BASH-014 + SEC-010 -> TEST-007 (Cluster G);
BASH-003 -> BASH-001/ARCH-009; PERF-008 -> ARCH-002; DEP-002 + DEP-007 -> ARCH-007;
TEST-001/REL-002 -> REL-001.
