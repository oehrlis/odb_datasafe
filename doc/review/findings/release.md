# Release Engineering Findings - odb_datasafe v0.20.4

**Scope:** Makefile, .github/workflows/ci.yml, .github/workflows/release.yml,
scripts/build.sh, VERSION, .extension, CHANGELOG.md

---

## Findings

### REL-001 - Test exit code masked in Makefile - bats failures do not fail CI

- **Severity:** Critical
- **Evidence:** `Makefile:127-129` (non-timeout branch) - `$(BATS) ... && echo "Tests passed" || echo "..."` -
  the `|| echo` replaces non-zero exit from BATS with zero. Timeout branch (`:117-126`) captures
  `rc=$$?` but has no `exit $$rc`, also exits zero for test failures.
- **Impact:** `make test` always exits 0 when tests fail. `make check` and `make ci` depend on
  `make test`, so they also pass silently on test failures.
- **Recommendation:** Remove `|| echo` from non-timeout branch. Add `exit $$rc` after `fi` in
  timeout branch.

---

### REL-002 - CI test job has `continue-on-error: true` - test failures are advisory only

- **Severity:** Critical
- **Evidence:** `.github/workflows/ci.yml:65` - `continue-on-error: true` on the "Run tests" step.
- **Impact:** PRs with failing unit tests can be merged. Test failures show as annotations, not
  blocking status.
- **Recommendation:** Remove `continue-on-error: true`. Combined with REL-001 fix, bats failures
  will block PRs.

---

### REL-003 - shfmt format-check absent from CI pipeline

- **Severity:** High
- **Evidence:** `Makefile:203-213` - `format-check` target exists but is not referenced in `lint`
  or CI workflow. Neither `ci.yml` nor `release.yml` call `format-check` or `shfmt`.
- **Recommendation:** Add `make format-check` as a step in the CI `lint` job between shellcheck
  and markdownlint. Gate as hard failure (no `continue-on-error`).

---

### REL-004 - Script header versions frozen at v0.19.1 across majority of bin/ scripts

- **Severity:** High
- **Evidence:** `bin/ds_target_list.sh:8`, `bin/ds_target_register.sh:8`, `lib/common.sh:8`,
  `lib/oci_helpers.sh:8`, `lib/ds_lib.sh:8`, `lib/ssh_helpers.sh:8` and many others - all show
  `Version.....: v0.19.1`. Package is at 0.20.4.
- **Recommendation:** Either update headers during the release bump via Makefile `version-bump-*`
  targets, or explicitly accept them as "last-touched" markers. `ds_database_prereqs.sh:28` has
  a hardcoded `SCRIPT_VERSION="0.19.0"` with no `.extension` dynamic read - this is the more
  actionable inconsistency.

---

### REL-005 - `install_datasafe_service.sh` carries private `SCRIPT_VERSION="v1.1.0"` out of sync

- **Severity:** Medium
- **Evidence:** `bin/install_datasafe_service.sh:27` - `SCRIPT_VERSION="v1.1.0"` hardcoded while
  package is 0.20.4. `bin/uninstall_all_datasafe_services.sh:23` same. This value is emitted in
  `--version` output and embedded in generated service files.
- **Recommendation:** Replace hardcoded literal with the same `.extension` parse pattern used by
  other scripts: `SCRIPT_VERSION="$(grep '^version:' ...")`

---

### REL-006 - Same-day patch cadence reveals absent pre-release validation gate

- **Severity:** High
- **Evidence:** 5 commits on 2026-06-25: `9d686e6`, `ee390ec`, `1739494`, `46a58ff`, `7082c9f`.
  Pattern: fix -> release -> discover regression -> fix -> release. v0.20.3 introduced a regression
  that v0.20.4 fixed (same day). No integration tests exist for the installer lifecycle.
- **Root cause:** `bin/install_datasafe_service.sh` has no BATS coverage for `--install` logic.
- **Recommendation:** Release target should require `make check` (lint + tests) as a precondition.
  Manual review step in pre-release checklist for the specific subsystem being patched.

---

### REL-007 - `make release` does not run lint or tests before bumping version

- **Severity:** High
- **Evidence:** `Makefile:330-340` - `release` depends only on `version-bump-patch` and `tag`;
  no `check` or `lint` dependency. A dirty or failing codebase can be released with
  `make release`.
- **Recommendation:** Add `check` as prerequisite: `release: check version-bump-patch tag`.

---

### REL-008 - Release workflow runs `make test` and `make ci` redundantly

- **Severity:** Low
- **Evidence:** `release.yml:73` - standalone `make test`; `release.yml:76` - `make ci` which
  includes `clean lint test build`. Tests run twice, wasting ~30 minutes of runner time.
- **Recommendation:** Remove the standalone `make test` step at `release.yml:72-73`.

---

### REL-009 - Tarball `.extension.checksum` contains UTC timestamp, breaking binary reproducibility

- **Severity:** Low
- **Evidence:** `scripts/build.sh:168` - `# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)` written
  into `.extension.checksum` before embedding in tarball. Two builds from same source produce
  different tarballs and different `.sha256` values.
- **Recommendation:** Replace timestamp with git commit hash or omit entirely. Set
  `SOURCE_DATE_EPOCH` for full tarball reproducibility.

---

### REL-010 - No documented v1.0.0 readiness gate or milestone checklist

- **Severity:** High
- **Evidence:** No file in the repository defines what "done" means for v1.0.0.
- **Recommendation:** Create `doc/milestone-v1.0.0.md` with explicit pass/fail criteria:
  all REL-001..REL-007 resolved, BATS pass rate 100%, CHANGELOG [Unreleased] empty at tag time,
  script header versions consistent, integration test coverage documented.

---

### REL-011 - Missing git tags for v0.19.2 and v0.19.3

- **Severity:** Low
- **Evidence:** Git tag list: `v0.19.1`, `v0.19.4` (no v0.19.2 or v0.19.3). Commit
  `6d792fe` ("chore: bump version to v0.19.2") exists but no tag pushed. CHANGELOG jumps
  from 0.19.1 to 0.17.3 (0.19.2-0.19.4 absent).
- **Recommendation:** Historical - cannot cleanly remediate. Going forward: `make release`
  with proposed check-gate ensures every bump produces a corresponding tag atomically.

---

### REL-012 - `[Unreleased]` CHANGELOG section is always empty

- **Severity:** Low
- **Evidence:** `CHANGELOG.md:9` - `## [Unreleased]` immediately followed by 0.20.4 entry,
  no content between them.
- **Recommendation:** Either use `[Unreleased]` as Keep-a-Changelog spec intends (accumulate
  during development, promote at release), or remove the section and document in contribution
  guide that entries are written at release time.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID     | Severity | Area                | One-line                                                      |
|--------|----------|---------------------|---------------------------------------------------------------|
| REL-001 | Critical | CI gate             | bats failure exit code masked in Makefile - tests never fail  |
| REL-002 | Critical | CI gate             | `continue-on-error: true` on CI test step                     |
| REL-003 | High     | CI gate             | shfmt format-check absent from CI pipeline                    |
| REL-004 | High     | Version metadata    | Script header versions frozen at v0.19.1                      |
| REL-006 | High     | Release process     | 5 same-day patches reveal absent pre-release validation gate  |
| REL-007 | High     | Release process     | `make release` runs without lint or test gate                 |
| REL-010 | High     | v1.0.0 gate         | No documented v1.0.0 readiness checklist                      |
| REL-005 | Medium   | Version metadata    | Private `SCRIPT_VERSION="v1.1.0"` in installer                |
| REL-008 | Low      | CI efficiency       | Release workflow runs `make test` and `make ci` twice         |
| REL-009 | Low      | Reproducibility     | Tarball timestamp breaks binary reproducibility               |
| REL-011 | Low      | Tag discipline      | Missing git tags v0.19.2 and v0.19.3                          |
| REL-012 | Low      | CHANGELOG           | `[Unreleased]` section always empty                           |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** Critical: 2, High: 5, Medium: 1, Low: 4
