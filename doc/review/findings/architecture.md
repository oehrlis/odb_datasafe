# Architecture Findings - odb_datasafe v0.20.4

**Scope:** lib/ (4 files), bin/ (template.sh, datasafe_env.sh, install_datasafe_service.sh,
ds_connector_create.sh, ds_target_register.sh), _scans/repo-structure.md,
_scans/static-findings.md, .extension, etc/env.sh

---

## Findings

### ARCH-001 - Installer is a self-contained God script that bypasses the entire framework

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:1-1372` (1372 lines, 0 references to
  `lib/ds_lib.sh` / `lib/common.sh`). Redefines `init_colors` (83-94), `print_message`
  (105-118), error routing, and its own arg parser (1219-1302) instead of using
  `lib/common.sh` functions.
- **Impact:** Two parallel framework implementations to maintain. Logging level vocabulary
  (`ERROR|SUCCESS|WARNING|INFO|STEP`) diverges from library (`TRACE|DEBUG|INFO|WARN|ERROR|FATAL`),
  so installer output cannot be filtered with `LOG_LEVEL`/`--quiet` and is not loggable via
  `LOG_FILE`. Every recent installer defect (v0.20.2-v0.20.4) was fixed only in this island.
- **Recommendation:** Source `lib/ds_lib.sh`; replace `print_message`/`init_colors` with library
  logging API; route system-mutation steps (`systemctl`, `cp`, `chown`) through a thin wrapper for
  uniform `--dry-run`. Keep installer-only logic (systemd unit generation, sudoers) local.
- **Consolidation opportunity:** yes

---

### ARCH-002 - Bootstrap boilerplate duplicated across every bin script with no shared init

- **Severity:** High
- **Evidence:** Identical 13-15 line bootstrap block in `bin/template.sh:18-34`,
  `bin/ds_connector_create.sh:22-35`, `bin/ds_target_register.sh:46-59`. The pattern is
  structural across ~25 bin scripts: SCRIPT_DIR / LIB_DIR / SCRIPT_NAME / version-grep-from-
  .extension / source ds_lib.sh.
- **Impact:** 25+ copies of the version-extraction grep and hardcoded fallback version literals
  that drift (see ARCH-010). Any change to the bootstrap contract requires touching every script.
- **Recommendation:** Extract a single `bin/.ds_bootstrap.sh` (or `ds_bootstrap` function) that
  resolves SCRIPT_DIR/LIB_DIR, sets SCRIPT_NAME/SCRIPT_VERSION from .extension, and sources
  ds_lib.sh. Bin scripts carry one `source` line.
- **Consolidation opportunity:** yes

---

### ARCH-003 - `is_ocid` defined twice with silent shadowing

- **Severity:** Medium
- **Evidence:** `lib/common.sh:566-568` and `lib/oci_helpers.sh:100-103` define `is_ocid` with
  identical behavior (`[[ "$1" =~ ^ocid1\. ]]`). `oci_helpers.sh` always loads after `common.sh`
  and silently shadows the first definition.
- **Impact:** Latent divergence trap - a future tweak to one copy will not propagate. OCID
  validation is used in ~30 guard clauses across the library. Ownership of the "what is an OCID"
  rule is ambiguous.
- **Recommendation:** Delete the `oci_helpers.sh` copy and rely on `common.sh`; or move canonical
  definition to `oci_helpers.sh` and remove from `common.sh`. Pick one home.
- **Consolidation opportunity:** yes

---

### ARCH-004 - Two identical BSD/GNU stat-mtime helpers in the same file

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:74-88` (`_ds_cache_mtime`) and `lib/oci_helpers.sh:1071-1085`
  (`_ds_file_mtime`) are byte-for-byte equivalent (try `stat -f '%m'`, fall back to `stat -c '%Y'`).
- **Impact:** Same fix needed in two places if portability logic changes.
- **Recommendation:** Delete `_ds_cache_mtime`; repoint the caller (around line 1283) to
  `_ds_file_mtime`.
- **Consolidation opportunity:** yes

---

### ARCH-005 - `oci_exec` and `oci_exec_ro` are near-identical; global-option injection copy-pasted

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:363-384` (`oci_exec`) and `lib/oci_helpers.sh:395-411`
  (`oci_exec_ro`) differ only in dry-run short-circuit (378-381). The same
  `--config-file/--profile/--region` append block is re-implemented inline in `ds_refresh_target`
  (`lib/oci_helpers.sh:1651-1653`), which also uses `2>&1` (`:1660`) - exactly the stderr-bleed
  anti-pattern the wrappers document at `:314-317`.
- **Impact:** "How OCI global options are applied" rule lives in three places. `ds_refresh_target`
  already drifted: dry-run and stderr handling are not uniform across all OCI calls.
- **Recommendation:** Factor global-option append into `_oci_global_opts`; have `oci_exec_ro`
  delegate to `oci_exec`; refactor `ds_refresh_target` to call the wrapper.
- **Consolidation opportunity:** yes

---

### ARCH-006 - Config-file naming mismatch: loader looks for `datasafe.conf`, repo ships `odb_datasafe.conf.example`

- **Severity:** Medium
- **Evidence:** `lib/common.sh:516` loads `${SCRIPT_DIR}/../etc/datasafe.conf`; `:511-513` loads
  `${ORADBA_ETC}/datasafe.conf`. Shipped templates: `etc/odb_datasafe.conf.example` and
  `etc/datasafe.conf.example`. A user copying `odb_datasafe.conf.example` to `odb_datasafe.conf`
  gets a config the loader silently ignores.
- **Impact:** Silent misconfiguration - `load_config` skips missing files without warning
  (`common.sh:472`). Same root-cause family as recent installer path defects.
- **Recommendation:** Pick one canonical filename; align example, loader, and docs. Have
  `init_config` log at INFO which config files it actually loaded.
- **Consolidation opportunity:** yes

---

### ARCH-007 - Hardcoded path assumptions in the installer break custom layouts (root cause of recent defect series)

- **Severity:** High
- **Evidence:** `bin/install_datasafe_service.sh:286-291` hardcodes candidate paths
  (`/appl/oracle/product`, `/u01/app/oracle/product`, `/u01/oracle/product`,
  `/opt/oracle/product`); `:30,33` defaults off `${ORACLE_BASE:-/u01/app/oracle}`; `:34` defaults
  `ORADBA_BASE` to `/opt/oradba`; systemd unit hardcodes `/bin/systemctl` (`:623-630`);
  `oradba_dsctl.sh` assembled as `${ORADBA_BASE}/bin/oradba_dsctl.sh` (`:570`) with only a
  post-hoc executability warning (`:942-946`).
- **Impact:** On distros where systemd lives at `/usr/bin/systemctl`, or installs under a non-
  listed Oracle base, prepare/install silently generate a broken unit or sudoers. The v0.20.2-
  v0.20.4 commit log ("auto-discover base", "fix log dir", "User= mismatch") confirms this is
  the active defect source. Validation happens too late.
- **Recommendation:** Centralize layout resolution into one discovery function with documented
  precedence (env override -> registry -> candidate scan). Resolve `systemctl` via `command -v`.
  Move all executable/User validation into `--prepare` so generated artifacts are correct at
  creation time.
- **Consolidation opportunity:** yes

---

### ARCH-008 - `--prepare` -> `--install` contract puts validation on the wrong side of the handoff

- **Severity:** Medium
- **Evidence:** `--prepare` writes Unit/sudoers artifacts (`install_datasafe_service.sh:793-899`).
  `--install` re-validates and silently calls `prepare_service` again to fix a `User=` mismatch
  (`:927-937`) and warns about non-executable `ExecStart` (`:939-946`). The "non-root prepares,
  root installs" boundary advertised at `:138-139` is not enforced.
- **Impact:** Leaky contract - `--install` mutates prepared artifacts, blurring the boundary.
  Silent re-preparation on user mismatch was itself a v0.20.3 bug fix.
- **Recommendation:** Have `--prepare` emit a manifest file (user, group, base, alias, exec path);
  have `--install` read and verify the manifest and refuse on mismatch (or require
  `--force-regenerate`). Move all artifact-correctness validation into `--prepare`.
- **Consolidation opportunity:** no

---

### ARCH-009 - `setup_error_handling` is opt-in and inconsistently engaged; ERR-trap is dormant for most bin scripts

- **Severity:** Medium
- **Evidence:** `lib/common.sh:734-736` only calls `setup_error_handling` when
  `AUTO_ERROR_HANDLING=true`; none of the read bin scripts set this. The static scan reports ~43%
  carry `set -euo pipefail`, and most bin scripts (including `template.sh`, `ds_target_register.sh`,
  `ds_connector_create.sh`) are in the WITHOUT list.
- **Impact:** The ERR trap / stacktrace framework (`common.sh:268-315`) is effectively dormant for
  most entry points. The framework's central value (uniform error reporting) is unrealized. The
  template itself does not demonstrate enabling error handling.
- **Recommendation:** Make the bootstrap (ARCH-002) the single place that enables `set -euo
  pipefail` + ERR trap, with a documented opt-out for scripts that legitimately need lax error
  handling. Update `template.sh` accordingly.
- **Consolidation opportunity:** yes

---

### ARCH-010 - Version metadata drifts across header comments, fallback literals, and `SCRIPT_VERSION`

- **Severity:** Low
- **Evidence:** `lib/common.sh:8` header says `v0.19.1`; `:738` comment says `(v4.0.0)`;
  `lib/ds_lib.sh:39` says `(v4.0.0)`; `bin/install_datasafe_service.sh:27` hardcodes
  `SCRIPT_VERSION="v1.1.0"` while package is 0.20.4. Bootstrap fallback literals: `'0.19.1'` at
  `bin/template.sh:25`, `bin/ds_connector_create.sh:27`, `bin/ds_target_register.sh:52`.
- **Impact:** `--version` output unreliable and varies by script. Undermines release hygiene at
  v1.0.0 boundary.
- **Recommendation:** Remove per-script fallback literals (have bootstrap fail loudly if .extension
  is unreadable). Drop stale `v4.0.0`/`v1.1.0` strings. Single source of truth: `.extension`.
- **Consolidation opportunity:** yes

---

### ARCH-011 - `resolve_*_to_vars` uses `eval` to set caller variables

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:1547-1571` (`resolve_compartment_to_vars`) and
  `lib/oci_helpers.sh:1582-1612` (`resolve_target_to_vars`) build assignments with
  `eval "${prefix}_OCID=\"$input\""`. The static scan reported "no eval" - this is an undocumented
  exception.
- **Impact:** Mild injection surface if a display-name ever contains shell metacharacters.
  Contradicts the otherwise clean "no eval" posture.
- **Recommendation:** Replace with `printf -v "${prefix}_OCID" '%s' "$input"` (bash 3.2+ safe,
  no eval).
- **Consolidation opportunity:** no

---

### ARCH-012 - `ssh_helpers.sh` loaded by every script but consumed by almost none

- **Severity:** Low
- **Evidence:** `lib/ds_lib.sh:32-36` unconditionally sources `ssh_helpers.sh` for all bin
  scripts. `ds_target_register.sh:13-19` explicitly advertises "without requiring SSH access".
  SSH functions appear targeted at a narrow set of remote-execution scripts.
- **Impact:** Minor coupling and startup cost; slightly misleading dependency graph.
- **Recommendation:** Either document that SSH is bundled in the full-stack loader (acceptable), or
  split into a lighter core loader plus opt-in `source ssh_helpers.sh` for the few scripts that
  need it.
- **Consolidation opportunity:** no

---

### ARCH-013 - `oci_helpers.sh` mixes generic OCI wrappers with Data Safe domain logic

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh` (2262 lines) contains both generic OCI primitives
  (`oci_exec`, `oci_resolve_compartment_ocid`) and Data Safe domain functions (`ds_list_targets`,
  `ds_collect_targets`, `ds_create_connector`, `ds_filter_targets_by_tags`). `lib/ds_lib.sh`
  (described as "Data Safe API wrappers") is in fact a 39-line loader.
- **Impact:** The named boundary (oci_helpers = OCI, ds_lib = Data Safe) does not match reality.
  No circular dependency; this is a cohesion issue.
- **Recommendation:** Split `ds_*` domain functions out of `oci_helpers.sh` into a real `ds_lib.sh`
  (or `ds_targets.sh` / `ds_connectors.sh`), leaving `oci_helpers.sh` as generic OCI plumbing.
- **Consolidation opportunity:** yes

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID       | Severity | Area                     | One-line                                                                |
|----------|----------|--------------------------|-------------------------------------------------------------------------|
| ARCH-001 | High     | God script / framework   | Installer reimplements framework logging, argparse, colors in 1372 LOC |
| ARCH-002 | High     | Bootstrap duplication    | 25+ bin scripts copy-paste identical 13-15 line init block             |
| ARCH-003 | Medium   | Duplication              | `is_ocid` defined and shadowed in 2 libraries                           |
| ARCH-004 | Low      | Duplication              | Two identical mtime helpers in same file                                |
| ARCH-005 | Medium   | OCI wrapper consistency  | `ds_refresh_target` bypasses `oci_exec` wrapper, reintroduces stderr   |
| ARCH-006 | Medium   | Config naming            | Loader looks for `datasafe.conf`; shipped example is `odb_datasafe.conf.example` |
| ARCH-007 | High     | Path assumptions         | Hardcoded Oracle/systemd paths - root cause of v0.20.2-v0.20.4 defects |
| ARCH-008 | Medium   | Install lifecycle        | `--install` mutates `--prepare` artifacts; leaky non-root/root boundary |
| ARCH-009 | Medium   | Error handling           | ERR trap opt-in and dormant; `template.sh` does not wire it up          |
| ARCH-010 | Low      | Version metadata         | Script headers, fallback literals, SCRIPT_VERSION stale/inconsistent   |
| ARCH-011 | Low      | eval                     | `resolve_*_to_vars` uses eval; not reported by static scan              |
| ARCH-012 | Low      | Coupling                 | `ssh_helpers.sh` loaded for all scripts, used by few                    |
| ARCH-013 | Low      | Library cohesion         | `oci_helpers.sh` owns Data Safe domain logic despite its name           |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** High: 3, Medium: 4, Low: 6
