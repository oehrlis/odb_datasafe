# odb_datasafe Repository Structure Inventory

**Scan Date:** 2026-06-28  
**Repository:** /Users/stefan.oehrli/Repos/own/oehrlis/odb_datasafe  
**Current Branch:** main  
**Current Version:** 0.20.4  
**Status:** Clean (no pending changes)

---

## Directory Tree (Depth 3)

```
.
├── bin/                     Entry point scripts for Data Safe management
├── lib/                     Shared library modules (OCI, common, SSH helpers)
├── sql/                     SQL scripts for DB prerequisites and privileges
├── scripts/                 Build and maintenance scripts
├── tests/                   BATS test suite (32 test files)
├── etc/                     Configuration templates and aliases
├── doc/                     Documentation and release notes
├── tasks/                   Project tracking (todo, lessons)
├── log/                     Runtime logs (ignored in git)
├── dist/                    Build artifacts (tarball, excluded from scan)
├── Makefile                 Development workflow automation
├── VERSION                  Version file (0.20.4)
├── .extension               Extension metadata (name, version, description)
├── CHANGELOG.md             Release history
├── README.md                Project overview
└── CLAUDE.md                AI configuration (project rules)
```

---

## File Count Summary

| File Type | Count | Notes |
|-----------|-------|-------|
| `.sh` | 40 | Bash scripts (bin, lib, scripts) |
| `.bats` | 32 | BATS test files |
| `.md` | 73 | Markdown documentation |
| `.sql` | 6 | SQL scripts for DB setup |
| `.yaml`/`.yml` | 2 | GitHub workflow configs |
| `.json` | 1 | `.markdownlint.json` |
| `.conf` | 0 | Configuration files |
| `.ini` | 0 | INI files |
| Other | 15 | LICENSE, Makefile, .extension, version-related, example configs |
| **Total** | **169** | Excluding .git and dist/ |

---

## Lines of Code (LOC) Summary

### By Directory

| Directory | File Type | Count | LOC | Avg Size |
|-----------|-----------|-------|-----|----------|
| `bin/` | `.sh` | 28 | 8,256 | 295 |
| `lib/` | `.sh` | 5 | 3,164 | 633 |
| `scripts/` | `.sh` | 3 | ~600 | 200 |
| `tests/` | `.bats`/`.bash`/`.sh` | 35 | 4,456 | 127 |
| `sql/` | `.sql` | 6 | UNKNOWN | - |
| **Total Executable Code** | | **76** | **~16,476** | - |

### Top 5 Largest Scripts (by LOC)

| Path | LOC | Purpose |
|------|-----|---------|
| `bin/ds_target_list.sh` | 2,829 | List Data Safe targets with filtering, formatting, export options |
| `bin/install_datasafe_service.sh` | 1,588 | Install/uninstall Data Safe connectors as systemd services |
| `bin/ds_target_register.sh` | 1,826 | Register new database targets with Data Safe |
| `bin/ds_database_prereqs.sh` | 1,910 | Configure database prerequisites (prerequisites, privileges, user creation) |
| `bin/ds_connector_update.sh` | 1,478 | Update connector configuration (IP, port, credentials) |

---

## Entry Points (bin/ scripts)

All executable scripts in `bin/` directory with shebang and first-line purpose:

| Script | Shebang | Purpose |
|--------|---------|---------|
| `odb_datasafe_help.sh` | `#!/usr/bin/env bash` | Display help overview of all Data Safe tools |
| `datasafe_help.sh` | `#!/usr/bin/env bash` | Legacy help script (maintained for compatibility) |
| `ds_version.sh` | `#!/usr/bin/env bash` | Display Data Safe extension version info |
| `ds_target_list.sh` | `#!/usr/bin/env bash` | List Oracle Data Safe target databases with summary or details |
| `ds_target_register.sh` | `#!/usr/bin/env bash` | Register new database target with Oracle Data Safe |
| `ds_target_refresh.sh` | `#!/usr/bin/env bash` | Refresh registered Data Safe target(s) assessment |
| `ds_target_delete.sh` | `#!/usr/bin/env bash` | Deregister/delete Data Safe target |
| `ds_target_details.sh` | `#!/usr/bin/env bash` | Display detailed information on single Data Safe target |
| `ds_target_activate.sh` | `#!/usr/bin/env bash` | Activate/enable Data Safe target for assessments |
| `ds_target_audit_trail.sh` | `#!/usr/bin/env bash` | Retrieve and display Data Safe audit trail for target |
| `ds_target_connector_summary.sh` | `#!/usr/bin/env bash` | Display connector summary for Data Safe target |
| `ds_target_connect_details.sh` | `#!/usr/bin/env bash` | Display connection details for Data Safe target |
| `ds_target_list_connector.sh` | `#!/usr/bin/env bash` | List connectors associated with Data Safe targets |
| `ds_target_export.sh` | `#!/usr/bin/env bash` | Export Data Safe target configuration/assessment data |
| `ds_target_update_credentials.sh` | `#!/usr/bin/env bash` | Update database credentials for Data Safe target |
| `ds_target_update_connector.sh` | `#!/usr/bin/env bash` | Update connector assignment for Data Safe target |
| `ds_target_update_tags.sh` | `#!/usr/bin/env bash` | Update tags on Data Safe target |
| `ds_target_update_service.sh` | `#!/usr/bin/env bash` | Update service configuration for Data Safe target |
| `ds_target_move.sh` | `#!/usr/bin/env bash` | Move Data Safe target to different compartment |
| `ds_target_reregister.sh` | `#!/usr/bin/env bash` | Re-register relocated PDB as Data Safe target |
| `ds_connector_create.sh` | `#!/usr/bin/env bash` | Create new Data Safe connector deployment |
| `ds_connector_register_oradba.sh` | `#!/usr/bin/env bash` | Register OraDBA-managed connector with Data Safe |
| `ds_connector_update.sh` | `#!/usr/bin/env bash` | Update connector configuration (IP, port, credentials) |
| `ds_find_untagged_targets.sh` | `#!/usr/bin/env bash` | Identify untagged Data Safe targets |
| `ds_tg_report.sh` | `#!/usr/bin/env bash` | Generate target group report for Data Safe |
| `ds_database_prereqs.sh` | `#!/usr/bin/env bash` | Configure database prerequisites (privileges, user creation) |
| `install_datasafe_service.sh` | `#!/usr/bin/env bash` | Install/uninstall Data Safe On-Premises Connector as systemd service |
| `uninstall_all_datasafe_services.sh` | `#!/usr/bin/env bash` | Uninstall all Data Safe connector services |
| `template.sh` | `#!/usr/bin/env bash` | Template for new Data Safe management scripts |
| `datasafe_env.sh` | `#!/usr/bin/env bash` | (Non-executable) Environment configuration source file |

**Total Entry Points:** 30 executable scripts

---

## Library Files (lib/)

| File | LOC | Purpose |
|------|-----|---------|
| `lib/common.sh` | ~1,200 | Utility functions (logging, error handling, formatting) |
| `lib/ds_lib.sh` | ~800 | Data Safe-specific OCI API wrappers |
| `lib/oci_helpers.sh` | ~800 | OCI CLI authentication and execution helpers |
| `lib/ssh_helpers.sh` | ~364 | SSH connection and bastion host utilities |
| `lib/README.md` | ~50 | Library documentation |

All library files follow OraDBA header format with `set -euo pipefail` enforcement.

---

## Configuration Files (etc/)

| File | Type | Purpose |
|------|------|---------|
| `etc/env.sh` | Shell source | Environment variable definitions |
| `etc/aliases.sh` | Shell source | Command aliases for Data Safe scripts |
| `etc/odb_datasafe.conf.example` | Configuration | Main configuration template |
| `etc/datasafe.conf.example` | Configuration | Legacy configuration template |
| `etc/pcy-ds-admin.json.example` | JSON | OCI IAM policy template (admin role) |
| `etc/pcy-ds-auditor.json.example` | JSON | OCI IAM policy template (auditor role) |
| `etc/pcy-ds-operation.json.example` | JSON | OCI IAM policy template (operator role) |
| `etc/pcy-ds-service.json.example` | JSON | OCI IAM policy template (service role) |

---

## SQL Scripts (sql/)

| File | Purpose |
|------|---------|
| `sql/datasafe_privileges.sql` | Grant Data Safe-required Oracle database privileges |
| `sql/create_ds_admin_user.sql` | Create Data Safe admin user account |
| `sql/create_ds_admin_prerequisites.sql` | Create prerequisites (roles, policies) for Data Safe admin |
| `sql/extension_comprehensive.sql` | Full dictionary query extension (v$datasafe_metrics) |
| `sql/extension_query.sql` | Query-only extension (read-only access) |
| `sql/extension_simple.sql` | Minimal extension (basic metrics only) |

---

## Test Files (tests/)

### Test Suite Breakdown

| Category | Count | Files |
|----------|-------|-------|
| Unit tests | 8 | `lib_*.bats`, `basic_functionality.bats` |
| Integration tests | 6 | `integration_*.bats` |
| Script-specific tests | 14 | `script_*.bats` |
| Helper tests | 3 | `template_helpers.bats`, `bash42_compatibility.bats`, `edge_case_tests.bats` |
| Test infrastructure | 1 | `test_helper.bash`, `run_tests.sh` |
| Documentation | 1 | `README.md` |
| **Total** | **33** | Test files + infrastructure |

### Notable Test Coverage

- **Functional coverage:** 227+ BATS tests documented in README
- **Performance tests:** bash 4.2 compatibility, subshell anti-patterns
- **Integration scope:** Parameter combinations, full workflow tests
- **Edge cases:** Empty inputs, boundary conditions, error scenarios

---

## CI/CD Configuration

### GitHub Workflows

Found in `.github/workflows/`:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| UNKNOWN | UNKNOWN | (No `.github/` directory found at root) |

**Status:** No GitHub Actions workflows configured in repository.

---

## Project Configuration Files (Root)

| File | Purpose |
|------|---------|
| `VERSION` | Semantic version: `0.20.4` |
| `.extension` | OraDBA extension metadata (name, version, description, priority) |
| `.markdownlint.json` | Markdown linting rules (line_length: 120, MD033: off) |
| `Makefile` | Development automation (test, lint, build, release, version management) |
| `CHANGELOG.md` | Release history (semver, conventional commits format) |
| `README.md` | Project overview and quick start guide |
| `CLAUDE.md` | AI assistant project configuration (rules, skills, workflow) |

---

## Version Markers

| File | Location | Version | Format |
|------|----------|---------|--------|
| `VERSION` | Root | `0.20.4` | Plain text (semantic version) |
| `.extension` | Root | `0.20.4` | YAML: `version: 0.20.4` |
| CHANGELOG | `CHANGELOG.md` line 11 | `0.20.4` | Markdown: `## [0.20.4] - 2026-06-25` |
| Script headers | `bin/ds_target_list.sh` line 9 | `v0.19.1` | Comment: `Version....: v0.19.1` |

**Version Drift Note:** Release notes show `v0.19.1` is latest in docs, but code is at `0.20.4`. Extension metadata and VERSION file are in sync.

---

## Git Log Summary: Last 20 Commits

| Date | Commit ID | Type | Scope | Message |
|------|-----------|------|-------|---------|
| 2026-06-25 21:13 | `7082c9f` | fix | install | Auto-discover base, auto-regen user mismatch, fix log dir - v0.20.4 |
| 2026-06-25 15:03 | `46a58ff` | fix | install | Detect User= mismatch and missing sudoers before install - v0.20.3 |
| 2026-06-25 13:30 | `1739494` | docs | release | Finalize CHANGELOG and release notes for v0.20.2 |
| 2026-06-25 13:28 | `ee390ec` | fix | version | Sync .extension to 0.20.2 |
| 2026-06-25 13:18 | `9d686e6` | fix | datasafe | Use oradba_dsctl.sh for systemd ExecStart/ExecStop - v0.20.2 |
| 2026-05-26 16:32 | `12a9ba8` | style | - | Clean up stray whitespace and shfmt formatting |
| 2026-05-26 15:39 | `c74c7ad` | fix | lib | Separate stderr in oci_exec wrappers - v0.20.1 |
| 2026-05-05 18:14 | `b5e007a` | docs | tasks | Fix markdownlint table alignment and blank lines in todo.md |
| 2026-05-05 18:04 | `aad2cff` | fix | reregister | Pass explicit exit code to usage() to silence SC2120 |
| 2026-05-05 17:30 | `40e2fa6` | chore | - | Prepare release 0.20.0 |
| 2026-05-05 17:12 | `0ccaf27` | docs | release | Add v0.20.0 release notes and changelog entry |
| 2026-05-05 16:42 | `37d8d8a` | feat | reregister | Add ds_target_reregister.sh for PDB relocation |
| 2026-05-05 11:40 | `bd9f99c` | fix | activate | Guard loop against ERR trap on single-target failure |
| 2026-05-03 08:18 | `52fa3e7` | docs | - | Fix markdown issue |
| 2026-05-03 07:32 | `0fe3e52` | docs | release | Add v0.19.4 release notes and changelog entry |
| 2026-05-03 07:27 | `121a8ac` | chore | - | Bump version to v0.19.4 |
| 2026-05-02 23:01 | `13a0ecd` | perf | bash | Eliminate in-loop subshell anti-patterns |
| 2026-04-08 11:47 | `70d2b77` | refactor | makefile | Align with OraDBA standard preamble and add release workflow |
| 2026-04-08 11:11 | `fb7813d` | fix | claude | Convert rules symlinks to real files, add readonly SCRIPT_VERSION |
| 2026-04-08 10:38 | `1f8a63a` | chore | claude | Add Claude Code configuration and project rules |

**Commit Types Distribution (last 20):**
- `fix`: 8
- `docs`: 5
- `chore`: 4
- `perf`: 1
- `feat`: 1
- `refactor`: 1
- `style`: 1

---

## Recent Git Activity

### Commits per Week (Last 3 Months: 2026-04-01 to 2026-06-28)

| Week Ending | Count | Notes |
|-------------|-------|-------|
| 2026-06-25 | 5 | Recent release push (v0.20.2, v0.20.3, v0.20.4) |
| 2026-05-26 | 2 | Maintenance (formatting, lib fixes) |
| 2026-05-05 | 6 | Major release (v0.20.0) + PDB reregister feature |
| 2026-05-03 | 3 | Release v0.19.4 + performance optimization |
| 2026-04-08 | 3 | Makefile refactor, Claude configuration |

**Total commits in last 3 months:** 20  
**Most recent activity:** 2026-06-25 (3 fixes in service installation)  
**Activity trend:** Consistent maintenance with periodic feature/release bursts

---

## AI Configuration Files

### Project Rules and Skills

Found at `./.claude/`:
- `.claude/rules/shell-scripts.md` - OraDBA shell script standards
- `.claude/rules/markdown-lint.md` - Markdown linting guidelines
- `.claude/rules/oci-naming.md` - OCI resource naming conventions

### Project Metadata

Found at `./`:
- `CLAUDE.md` - Project AI configuration (GitHub rules, workflow, quick reference)
- `./.extension` - Extension metadata (name, version, description, features)

---

## Build and Distribution

### Build Process

- **Build script:** `scripts/build.sh`
- **Output:** Tarball to `dist/` directory
- **Trigger:** `make build`
- **Contents:** Extension package with bin/, lib/, sql/, etc/, doc/

### Makefile Targets (Development)

| Target | Purpose |
|--------|---------|
| `test` | Run BATS tests (excluding integration) |
| `test-all` | Run all tests including integration |
| `lint` | Run shell + markdown lint checks |
| `format` | Format shell scripts with shfmt |
| `check` | Run lint + test |
| `build` | Build extension tarball |
| `clean` | Remove build artifacts |
| `release` | Full patch release workflow |
| `tag` | Create git tag from VERSION |
| `version-bump-patch/minor/major` | Bump semantic version |

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total files** | 169 |
| **Bash scripts (.sh)** | 40 |
| **Test files (.bats)** | 32 |
| **Markdown files (.md)** | 73 |
| **SQL scripts (.sql)** | 6 |
| **Total executable LOC** | ~16,476 |
| **Entry point scripts** | 30 |
| **Library modules** | 5 |
| **Test coverage** | 227+ BATS tests |
| **Current version** | 0.20.4 |
| **Latest commit date** | 2026-06-25 |
| **Recent commits (20)** | 20 |
| **Commit velocity (3 months)** | 20 commits / 12 weeks ≈ 1.7 per week |

---

## Notes

1. **Distribution excluded:** `dist/` directory and `.git/` are not included in file counts.
2. **Version drift:** Script headers reference v0.19.1; package version is 0.20.4. Extension metadata (.extension, VERSION) are synchronized.
3. **Test infrastructure:** Tests include BATS test files, helper scripts (test_helper.bash, run_tests.sh), and README.
4. **Performance optimization:** Recent commits (2026-05-02) eliminated bash subshell anti-patterns in loops.
5. **Release cadence:** Active maintenance with 3 releases in past 3 days (v0.20.2, v0.20.3, v0.20.4).
6. **GitHub Actions:** No CI/CD workflows found in repository.
7. **Documentation:** Comprehensive with README, CHANGELOG, release notes archive, and inline script headers.

---

*Inventory generated without analysis or recommendations. Raw structured data only.*
