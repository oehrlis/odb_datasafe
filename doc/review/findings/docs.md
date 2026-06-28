# Documentation Findings - odb_datasafe v0.20.4

**Scope:** README.md, CHANGELOG.md, doc/index.md, doc/install_datasafe_service.md,
doc/database_prereqs.md, doc/quickstart_root_admin.md, doc/standalone_usage.md,
doc/testing.md, lib/README.md, doc/release_notes/v0.20.4.md

---

## Findings

### DOC-001 - README and doc/index.md: stale "Latest Release" version

- **Severity:** High
- **Evidence:** `README.md:4` - `Latest Release: v0.19.1`; `doc/index.md:7` - same stale pointer.
  Package is at v0.20.4.
- **Recommendation:** Update both files to reference v0.20.4. Consider deriving the pointer from
  the VERSION file rather than maintaining it manually.

---

### DOC-002 - README: contradictory test count claims

- **Severity:** High
- **Evidence:** `README.md:134,155` - "127+ BATS tests"; `README.md:135` - "227+ BATS tests";
  `doc/index.md:19` - "287+ tests"; `tests/README.md:98` - "227+".
- **Recommendation:** Align README.md to a single authoritative count. Remove the 127+
  occurrences; use 227+ or derive from actual count.

---

### DOC-003 - README and doc/index.md: script count "16+" vs actual 30

- **Severity:** Medium
- **Evidence:** `README.md:152` and `doc/index.md:127` show "16+ executable scripts". Inventory
  confirms 30 entry points in `bin/`. `doc/index.md` Available Scripts table lists only 18.
  Missing: `ds_target_activate.sh`, `ds_target_audit_trail.sh`, `ds_connector_create.sh`,
  `ds_connector_register_oradba.sh`, `ds_target_reregister.sh`, `ds_find_untagged_targets.sh`,
  `ds_target_update_tags.sh`, `ds_tg_report.sh`, `odb_datasafe_help.sh`, `datasafe_help.sh`,
  `ds_version.sh`, and more.
- **Recommendation:** Update script count to 28+ (excluding template.sh, datasafe_env.sh as
  non-entry-point). Expand the Available Scripts table to include all executable scripts.

---

### DOC-004 - Script header versions frozen at v0.19.1 in most of bin/ and all of lib/

- **Severity:** Medium
- **Evidence:** `bin/ds_target_list.sh:8`, `bin/ds_target_register.sh:8`, `lib/common.sh:8`,
  `lib/oci_helpers.sh:8`, `lib/ds_lib.sh:8`, `lib/ssh_helpers.sh:8` all show `v0.19.1`.
  `bin/install_datasafe_service.sh` header correctly shows `v0.20.4` but `SCRIPT_VERSION` at `:27`
  is hardcoded `v1.1.0` - split identity.
- **Recommendation:** Treat header `Version.....:` as "last-touched" marker; update during release
  bump via Makefile. The installer split (header v0.20.4, runtime SCRIPT_VERSION v1.1.0) is the
  more actionable inconsistency.

---

### DOC-005 - doc/install_datasafe_service.md: documents `--remove` flag that does not exist

- **Severity:** High
- **Evidence:** `doc/install_datasafe_service.md:172` - `-r, --remove` in Command-Line Options
  table. `doc/quickstart_root_admin.md:162` - `--remove` in example. Actual parser accepts
  `--uninstall`, not `--remove`. Passing `--remove` hits unknown-option branch and exits 1.
- **Recommendation:** Replace all occurrences of `--remove` with `--uninstall` in both docs.

---

### DOC-006 - doc/install_datasafe_service.md: options table omits `--prepare`, `--install`, `--uninstall`

- **Severity:** Medium
- **Evidence:** `doc/install_datasafe_service.md:228-243` - formal options table lists `-l`,
  `-c`, `-r` but omits the three primary workflow modes.
- **Recommendation:** Add `--prepare`, `--install`, and `--uninstall` to the options table with
  their root-requirement note.

---

### DOC-007 - doc/install_datasafe_service.md: `CONNECTOR_BASE` auto-discovery not documented

- **Severity:** Medium
- **Evidence:** `doc/install_datasafe_service.md:261` documents the `CONNECTOR_BASE` default but
  does not mention the v0.20.4 `find_connector_base()` auto-discovery behavior introduced to fix
  the v0.20.2 defects.
- **Recommendation:** Add a note explaining that when the connector is not found at `CONNECTOR_BASE`,
  the script probes candidate paths (`/appl/oracle/product`, `/u01/app/oracle/product`, etc.)
  automatically.

---

### DOC-008 - doc/index.md: broken link to non-existent v0.19.0.md release note

- **Severity:** Medium
- **Evidence:** `doc/index.md:31` links to `release_notes/v0.19.0.md` which does not exist.
  Earliest available is v0.19.1.md.
- **Recommendation:** Change link to `v0.19.1.md` and update the annotation, or remove the
  stale pointer.

---

### DOC-009 - doc/index.md and doc/standalone_usage.md: reference non-existent `etc/.env.example`

- **Severity:** High
- **Evidence:** `doc/index.md:54` - `cp etc/.env.example .env`; `doc/standalone_usage.md:35` -
  same. File `etc/.env.example` does not exist. Actual templates: `etc/datasafe.conf.example`
  and `etc/odb_datasafe.conf.example`.
- **Recommendation:** Replace `etc/.env.example` with `etc/datasafe.conf.example`. Verify
  whether `lib/common.sh` `init_config` looks for a `.env` file.

---

### DOC-010 - lib/README.md: v4.0.0 framing, wrong LOC estimates, ssh_helpers.sh absent

- **Severity:** Medium
- **Evidence:** `lib/README.md:1` - "Data Safe v4.0.0 Library Documentation". LOC estimates:
  `common.sh` "~350 lines" (actual ~1,200), `oci_helpers.sh` "~450 lines" (actual ~800+).
  `lib/ssh_helpers.sh` (364 LOC) not mentioned anywhere.
- **Recommendation:** Remove the v4.0.0 version marker. Update LOC estimates. Add
  `ssh_helpers.sh` to the library structure section.

---

### DOC-011 - doc/testing.md: stale version (0.7.1), conflicting test counts (227 vs 163)

- **Severity:** Low
- **Evidence:** `doc/testing.md:540` - "As of v0.7.1... 227+ tests"; `:709-716` Performance
  Targets table shows "163+". Footer shows `Version: 0.7.1` and `Last Updated: 2026-02-11`.
- **Recommendation:** Update to current version 0.20.4. Resolve the 227 vs 163 contradiction.

---

### DOC-012 - tests/README.md: references v0.9.0, incomplete script coverage table

- **Severity:** Low
- **Evidence:** `tests/README.md:1` - "v0.9.0". Script Coverage section lists only 7 scripts
  as covered; current test suite has specific test files for many more.
- **Recommendation:** Update version to 0.20.4 and enumerate current test files.

---

### DOC-013 - CHANGELOG: missing entries for v0.19.2, v0.19.3, v0.19.4

- **Severity:** Medium
- **Evidence:** `CHANGELOG.md` jumps from `## [0.19.1]` to `## [0.17.3]`. Release note files
  exist for v0.19.2-v0.19.4 in `doc/release_notes/` but CHANGELOG has no entries for them.
- **Recommendation:** Add CHANGELOG entries for v0.19.2, v0.19.3, v0.19.4 sourced from their
  release note files.

---

### DOC-014 - README.md: "new in v0.6.1" annotation is anachronistic

- **Severity:** Low
- **Evidence:** `README.md:78` - `# Show targets grouped by connector (new in v0.6.1)`.
  Current version is 0.20.4.
- **Recommendation:** Remove the "new in v0.6.1" parenthetical.

---

### DOC-015 - doc/install_datasafe_service.md: Example 1 implies single-step installation

- **Severity:** Low
- **Evidence:** `doc/install_datasafe_service.md:562-579` - Quick Installation example shows
  root running script without `--install` flag. Default mode is `--prepare`, not `--install`.
- **Recommendation:** Update Example 1 to show the two-phase workflow (prepare as oracle,
  install as root) or explicitly label it as an `--install` invocation.

---

### DOC-016 - No onboarding documentation for `ds_connector_create.sh` (added v0.18.0)

- **Severity:** Medium
- **Evidence:** `ds_connector_create.sh` is a major new capability (end-to-end connector
  creation including OCI object creation, bundle download, setup.py install, HA-node mode)
  but has no dedicated section in any guide. Not listed in `doc/index.md` script table.
- **Recommendation:** Add at least a usage summary to `doc/install_datasafe_service.md` or
  `doc/index.md`, distinguishing it from the service installer. Document `--ha-node` mode
  and `--register-oradba` integration.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID     | Severity | Category   | Short title                                                        |
|--------|----------|------------|--------------------------------------------------------------------|
| DOC-001 | High    | Inaccurate | README/index latest release shows v0.19.1 (actual: v0.20.4)       |
| DOC-002 | High    | Inaccurate | README test counts contradictory (127 vs 227 vs 287)               |
| DOC-005 | High    | Inaccurate | `--remove` flag documented but does not exist (`--uninstall`)      |
| DOC-009 | High    | Inaccurate | `etc/.env.example` referenced in two docs; file does not exist     |
| DOC-003 | Medium  | Inaccurate | Script count "16+" vs actual 30                                    |
| DOC-004 | Medium  | Inaccurate | Script header Version frozen at v0.19.1; installer split identity  |
| DOC-006 | Medium  | Absent     | `--prepare`, `--install`, `--uninstall` missing from options table  |
| DOC-007 | Medium  | Inaccurate | CONNECTOR_BASE auto-discovery (v0.20.4) not documented             |
| DOC-008 | Medium  | Inaccurate | Broken link to `v0.19.0.md` (does not exist)                       |
| DOC-010 | Medium  | Inaccurate | lib/README.md: v4.0.0 framing, wrong LOC, ssh_helpers.sh absent    |
| DOC-013 | Medium  | Absent     | CHANGELOG missing v0.19.2, v0.19.3, v0.19.4 entries               |
| DOC-016 | Medium  | Absent     | No onboarding docs for `ds_connector_create.sh` (added v0.18.0)   |
| DOC-011 | Low     | Inaccurate | doc/testing.md version 0.7.1, conflicting test counts              |
| DOC-012 | Low     | Inaccurate | tests/README.md version 0.9.0, incomplete coverage table           |
| DOC-014 | Low     | Inaccurate | "new in v0.6.1" anachronistic annotation in README                 |
| DOC-015 | Low     | Inaccurate | Install example 1 implies single-step installation                 |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** High: 4, Medium: 8, Low: 4
