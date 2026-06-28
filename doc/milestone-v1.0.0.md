# v1.0.0 Readiness Checklist

This checklist gates the v1.0.0 tag. Every item must be confirmed green before
tagging. See `doc/review/roadmap.md` — "v1.0.0 readiness checklist" for the
authoritative source.

---

## CI and Quality Gates

- [x] `make ci` exits 0 on a clean checkout (clean lint format-check test build)
- [x] ShellCheck `--shell=bash`: zero warnings across `bin/` and `lib/`
- [x] `make format-check` (`shfmt -d`): no diff
- [x] All BATS tests green; no `status 0 or 1` zero-signal assertions remain (346 tests)

## Regression Tests

- [x] REG-001 `find_connector_base()` non-default base: exit 0; detected base in output
- [x] REG-002 `find_connector_base()` no candidate: exit non-zero; "not found" in output
- [x] REG-003 `install_service()` User= mismatch: regeneration warning; `User=bob` in service file
- [x] REG-004 `install_service()` missing sudoers: "Sudoers file not found" in output
- [x] REG-005 `install_service()` missing ExecStart: "ExecStart binary not found" in output
- [x] REG-006 Log directory creation: "Creating connector log directory" in output
- [x] REG-007 `oci_exec` stderr isolation: returns only JSON when oci emits warning to stderr
- [x] REG-008 DELETED target registration: registration proceeds; exit 0
- [x] REG-009 `ds_target_update_service.sh` PUT: `target-database get` before `update`
- [x] REG-010 `ds_target_activate.sh` multi-target: partial-success exit code; script does not abort
- [x] REG-011 `normalize_secret_value` file path: returns file contents
- [x] REG-012 `normalize_secret_value` literal: returns literal string unchanged

## Risk Register Blockers (nine v1.0.0 blockers)

- [x] REL-001 closed: `make test` exit code propagates bats failures
- [x] ORA-001 closed: no hardcoded password in source (`grep -R "DS_Admin.2025" .` == 0)
- [x] TEST-002 closed: `find_connector_base()` has regression coverage (REG-001/002)
- [x] TEST-003 closed: User= mismatch auto-regeneration has regression test (REG-003)
- [x] ARCH-007 closed: no hardcoded Oracle/systemd paths outside layout resolver
- [x] REL-007 closed: `make release` requires passing `make check`
- [x] REL-006 closed: release gate prevents same-day patch regressions
- [x] SEC-002 closed: no secret passed on argv; file:// pattern used
- [x] SEC-004 closed: temp credential files use mktemp + umask 077 + EXIT trap

## Security

- [x] No secret on argv or at a predictable plaintext path (audited)
- [x] Installer `--prepare`/`--install --dry-run` pass on Linux AND macOS
- [x] bash 4.0+ guard active; requirement documented in README

## Documentation and Release

- [x] CHANGELOG complete (0.19.2..current entries); no `[Unreleased]` section
- [x] README/docs version strings derived from `VERSION`; no stale literals
- [x] `VERSION` and `.extension` in sync (1.0.0)
- [x] `grep -R "v1.1.0|v4.0.0" doc/ lib/README.md` == 0 (stale strings cleared)
- [x] `grep -R "--remove" doc/ README.md` == 0; `--uninstall` documented
- [x] markdownlint clean across all touched docs

## Milestones Completed

- [x] M1 — Release Gate Restoration (v0.21.0): CI gate, hardcoded password removed, bash guard
- [x] M2 — Security Hardening (v0.22.0): argv exposure, Oracle privileges, installer security
- [x] M3 — Installer Hardening (v0.23.0): ERR/EXIT traps, stderr routing, REG-001..006 green
- [x] M4 — Test Coverage & Robustness (v0.24.0): 346 tests, PERF-012 bounded parallelism done
- [x] M5 — Documentation & Polish (v1.0.0): ARCH-013 domain migration, doc accuracy, dedup

## Previously Deferred — Now Done

- [x] PERF-012 (bounded parallelism) — completed in M4 (v0.24.0)
- [x] ARCH-013 (ds_* domain logic to lib/ds_lib.sh) — completed in M5 (v1.0.0)

## Sign-off

- [ ] Human sign-off recorded (GATE 2 approval)
- [ ] `git log --oneline -5` shows the v1.0.0 tag on main

---

*Created in M1. Fully checked in M5 — pending GATE 2 human sign-off.*
*Authoritative source: `doc/review/roadmap.md` — "v1.0.0 readiness checklist"*
