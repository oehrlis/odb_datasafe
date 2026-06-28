# v1.0.0 Readiness Checklist

This checklist gates the v1.0.0 tag. Every item must be confirmed green before
tagging. See `doc/review/roadmap.md` — "v1.0.0 readiness checklist" for the
authoritative source.

---

## CI and Quality Gates

- [ ] `make ci` exits 0 on a clean checkout (clean lint format-check test build)
- [ ] ShellCheck `--shell=bash`: zero warnings across `bin/` and `lib/`
- [ ] `make format-check` (`shfmt -d`): no diff
- [ ] All BATS tests green; no `status 0 or 1` zero-signal assertions remain

## Regression Tests

- [ ] REG-001 `find_connector_base()` non-default base: exit 0; detected base in output
- [ ] REG-002 `find_connector_base()` no candidate: exit non-zero; "not found" in output
- [ ] REG-003 `install_service()` User= mismatch: regeneration warning; `User=bob` in service file
- [ ] REG-004 `install_service()` missing sudoers: "Sudoers file not found" in output
- [ ] REG-005 `install_service()` missing ExecStart: "ExecStart binary not found" in output
- [ ] REG-006 Log directory creation: "Creating connector log directory" in output
- [ ] REG-007 `oci_exec` stderr isolation: returns only JSON when oci emits warning to stderr
- [ ] REG-008 DELETED target registration: registration proceeds; exit 0
- [ ] REG-009 `ds_target_update_service.sh` PUT: `target-database get` before `update`
- [ ] REG-010 `ds_target_activate.sh` multi-target: partial-success exit code; script does not abort
- [ ] REG-011 `normalize_secret_value` file path: returns file contents
- [ ] REG-012 `normalize_secret_value` literal: returns literal string unchanged

## Risk Register Blockers (nine v1.0.0 blockers)

- [ ] REL-001 closed: `make test` exit code propagates bats failures
- [ ] ORA-001 closed: no hardcoded password in source (`grep -R "DS_Admin.2025" .` == 0)
- [ ] TEST-002 closed: `find_connector_base()` has regression coverage (REG-001/002)
- [ ] TEST-003 closed: User= mismatch auto-regeneration has regression test (REG-003)
- [ ] ARCH-007 closed: no hardcoded Oracle/systemd paths outside layout resolver
- [ ] REL-007 closed: `make release` requires passing `make check`
- [ ] REL-006 closed: release gate prevents same-day patch regressions
- [ ] SEC-002 closed: no secret passed on argv; file:// pattern used
- [ ] SEC-004 closed: temp credential files use mktemp + umask 077 + EXIT trap

## Security

- [ ] No secret on argv or at a predictable plaintext path (audited)
- [ ] Installer `--prepare`/`--install --dry-run` pass on Linux AND macOS
- [ ] bash 4.0+ guard active; requirement documented in README

## Documentation and Release

- [ ] CHANGELOG complete (0.19.2..current entries); no `[Unreleased]` section
- [ ] README/docs version strings derived from `VERSION`; no stale literals
- [ ] `VERSION` and `.extension` in sync
- [ ] `grep -R "v0.19.1|v1.1.0|v4.0.0" doc/ lib/README.md bin/` == 0 (stale strings)
- [ ] `grep -R "--remove" doc/ README.md` == 0; `--uninstall` documented
- [ ] markdownlint clean across all touched docs

## Deferrals

- [ ] PERF-012 (bounded parallelism) recorded as v1.1 deferral in roadmap Clarifications
- [ ] ARCH-013 (ds_* domain logic to lib/ds_lib.sh) recorded as v1.1 deferral

## Sign-off

- [ ] Human sign-off recorded (GATE 2 approval)
- [ ] `git log --oneline -5` shows the v1.0.0 tag on main

---

*Created in M1. Updated milestone-by-milestone as items are confirmed.*
*Authoritative source: `doc/review/roadmap.md` — "v1.0.0 readiness checklist"*
