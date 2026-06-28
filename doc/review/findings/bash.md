# Bash Robustness Findings - odb_datasafe v0.20.4

**Scope:** lib/common.sh, lib/ds_lib.sh, lib/oci_helpers.sh, bin/install_datasafe_service.sh,
bin/ds_target_register.sh, bin/datasafe_env.sh

---

## Findings

### BASH-001 - Deferred `setup_error_handling` leaves bootstrap phase unprotected

- **Severity:** High
- **Evidence:** `bin/ds_target_register.sh:1293` - `setup_error_handling` called inside `main()`,
  after `init_config`, `parse_common_opts`, and `parse_args`. Same deferred pattern in all 19
  scripts that use the function.
- **Impact:** `set -euo pipefail` and ERR trap not active during `init_config` (which sources
  `.env` and `datasafe.conf`), `parse_common_opts`, and `parse_args`. A failed command
  substitution, corrupt config, or missing variable in this window proceeds silently with
  corrupt state.
- **Recommendation:** Move `setup_error_handling` to the very top of each script's execution,
  before `init_config`.

---

### BASH-002 - Two `bin/` scripts have no error protection at all

- **Severity:** High
- **Evidence:** `bin/ds_connector_register_oradba.sh` and `bin/ds_connector_update.sh` - neither
  has `set -euo pipefail` nor calls `setup_error_handling`. All OCI CLI calls in these scripts
  run without error propagation; failures silently return 0.
- **Recommendation:** Add `set -euo pipefail` at top and call `setup_error_handling` at start
  of `main()`.

---

### BASH-003 - Libraries loaded without active `set -e`; ERR trap framework is dormant

- **Severity:** Medium
- **Evidence:** `lib/common.sh:734` - `AUTO_ERROR_HANDLING` defaults to `false`. Module-level
  initialization in `oci_helpers.sh` runs without `set -e`. Every script sources `ds_lib.sh`
  before calling `setup_error_handling`, so library init runs under no error protection.
- **Recommendation:** Document the gap explicitly with a comment at the top of each library.

---

### BASH-004 - Bare `((count++))` under `set -e` in `ds_target_move.sh`

- **Severity:** Medium
- **Evidence:** `bin/ds_target_move.sh:518,564,610` - three bare `((count++))` where `count`
  starts at 0. Currently inside `if ... then` blocks (exempt from `set -e` abort), but fragile
  if ever refactored.
- **Recommendation:** Apply `|| true` consistently: `((count++)) || true`. Pattern already
  established in `ds_target_details.sh:742,744`.

---

### BASH-005 - `((frame++))` in `stacktrace()` - safe but context-dependent

- **Severity:** Low
- **Evidence:** `lib/common.sh:254` - inside `while` loop body (exempt from `set -e`).
- **Recommendation:** Add `|| true` for clarity: `((frame++)) || true`.

---

### BASH-006 - `install_datasafe_service.sh`: non-ERROR messages go to stdout, not stderr

- **Severity:** Low
- **Evidence:** `bin/install_datasafe_service.sh:111-118` - `print_message` routes only `ERROR`
  to stderr; `SUCCESS`, `WARNING`, `INFO`, `STEP` go to stdout. `lib/common.sh` routes all
  levels to stderr. The installer is the only diverging script.
- **Impact:** When installer output is captured (e.g. in automation), INFO/WARNING/STEP
  messages corrupt the captured output.
- **Recommendation:** Route all `print_message` output to stderr. Echo structured output
  (file paths, etc.) explicitly to stdout if needed.

---

### BASH-007 - OCI `--query` expression embeds unsanitized compartment name

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:671` - `--query "data[?name=='${input}'].id | [0]"`.
  If `${input}` contains a single quote, JMESPath expression is malformed. Silent correctness
  failure: a compartment named `it's-dept` would not be found.
- **Recommendation:** Use the structured search approach (already used elsewhere) or validate
  compartment names against `^[A-Za-z0-9 ._\-]+$` before passing to the query.

---

### BASH-008 - Shell variable interpolated directly into jq filter strings

- **Severity:** Medium
- **Evidence:** `bin/ds_target_register.sh:905` - `jq -r ".data[] | select(.\"display-name\" == \"$CONNECTOR\") | .id"`;
  `:958` - same pattern with `$DISPLAY_NAME`. Both embed variables directly in double-quoted
  filter strings. Rest of codebase correctly uses `jq --arg name "$input" '... | $name'`.
- **Impact:** If display name contains `"`, `\`, or jq metacharacters, filter is malformed or
  logic-injected.
- **Recommendation:** Replace both with `--arg` pattern:
  `jq -r --arg name "$CONNECTOR" '.data[] | select(."display-name" == $name) | .id'`

---

### BASH-009 - `echo "$var" | jq`/`tr` subshell patterns in library functions

- **Severity:** Low
- **Evidence:**
  - `lib/oci_helpers.sh:771` - `$(echo "$lifecycle_input" | tr '[:lower:]' '[:upper:]' | tr -d ' ')` (2 forks)
  - `lib/oci_helpers.sh:1397` - `$(echo "$matches" | wc -l | tr -d ' ')` (3 forks)
  - `lib/oci_helpers.sh:1400,1401` - nested `echo ... | cut` subshells
- **Recommendation:** Use bash built-ins: `${var^^}`, `${#array[@]}`, field extraction via
  IFS/parameter expansion. Violates the project's own `bash-performance.md` rule.

---

### BASH-013 - `generate_bundle_key` has unbounded `while true` loop

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:2202-2213` - no iteration limit. If `openssl` is unavailable
  or fails, could spin indefinitely in environments where the pipeline silently produces empty
  output.
- **Recommendation:** Add max iteration count: `local attempts=0; ((attempts >= 20)) && die "generate_bundle_key: failed after 20 attempts"`.

---

### BASH-014 - `ds_refresh_target` uses `2>&1` merge, bypassing `_oci_run_capture` design

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:1660` - `if output=$("${refresh_cmd[@]}" 2>&1)`. This
  bypasses `_oci_run_capture` which was specifically written to prevent Python warnings from
  contaminating stdout JSON.
- **Impact:** Python deprecation warnings, file-permission warnings, progress-bar output from
  OCI CLI stderr are merged into `$output` and can corrupt subsequent jq parsing.
- **Recommendation:** Refactor `ds_refresh_target` to use `oci_exec` wrapper.

---

### BASH-015 - `register_target` writes credentials to predictable temp path without cleanup trap

- **Severity:** High
- **Evidence:** `bin/ds_target_register.sh:1109` - `json_file="${TMPDIR:-/tmp}/ds_target_${DISPLAY_NAME//...}.json"`.
  Contains plaintext `DS_SECRET` at `:1167`. Predictable filename. On failure, deliberately
  preserved (`:1212`). No EXIT trap removes the file.
- **Impact:** Process interrupt (Ctrl-C, SIGTERM) between write and rm leaves credentials on
  disk with no cleanup. Predictable name enables TOCTOU race.
- **Recommendation:** Use `mktemp`. Register EXIT cleanup trap. On failure, write `****`-masked
  copy and delete the real one.

---

### BASH-016 - `install_datasafe_service.sh` has no ERR trap or EXIT cleanup

- **Severity:** Medium
- **Evidence:** `bin/install_datasafe_service.sh:21` - `set -euo pipefail` present but no
  `trap error_handler ERR` or `trap cleanup EXIT`. Script does not source `ds_lib.sh`.
- **Impact:** When a step fails, script exits via `set -e` with no diagnostic and may leave
  partial installation (service file copied, not enabled; sudoers copied but visudo failed).
  No rollback.
- **Recommendation:** Add `trap error_handler ERR` and cleanup trap. Or source `lib/common.sh`
  and call `setup_error_handling`.

---

### BASH-018 - No `LC_ALL=C` on locale-sensitive operations

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:771` - `tr '[:lower:]' '[:upper:]'` on lifecycle filter
  strings. In non-C locales, character collation may not match ASCII assumptions.
- **Recommendation:** Add `export LC_ALL=C` near top of `lib/common.sh` initialization.

---

### BASH-019 - `eval` used to set dynamic variable names from OCI API response values

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:1555-1566` and `:1591-1607` - eight `eval "${prefix}_OCID=\"$input\""` calls.
  `$input` comes from OCI API responses. The static scan incorrectly reported "no eval".
- **Impact:** A compartment name containing `"` or `$()` could inject code. Currently controlled
  (callers pass literal prefixes), but functions are documented as general utilities.
- **Recommendation:** Replace with `printf -v "${prefix}_OCID" '%s' "$input"` (bash 4.2+, no eval).

---

### BASH-020 - `is_ocid` defined in two files with silent shadowing

- **Severity:** Low
- **Evidence:** `lib/common.sh:566` and `lib/oci_helpers.sh:100` - identical implementations.
  `oci_helpers.sh` always loaded after `common.sh`, silently shadows the first.
- **Recommendation:** Remove `is_ocid` from `lib/oci_helpers.sh`.

---

### BASH-021 - `mapfile` used throughout; requires bash 4.0; macOS ships bash 3.2

- **Severity:** Medium
- **Evidence:** 15 occurrences across bin/. See DEP-001 for complete list.
- **Recommendation:** Consolidated with DEP-001: add runtime bash version guard.

---

### BASH-023 - `install_service` auto-regenerates service files without atomicity

- **Severity:** Medium
- **Evidence:** `bin/install_datasafe_service.sh:929-936` - on User= mismatch calls
  `prepare_service` then `chown "${CONNECTOR_ETC}"/*` with `2>/dev/null || true`.
  Glob chown with masked failure on security-critical service files.
- **Recommendation:** Do not suppress chown errors for service files. Consider making
  regeneration a separate validation step rather than inline auto-fix.

---

### BASH-024 - `discover_connectors` may fail on bash 4.3 and below with empty array + `set -u`

- **Severity:** Low
- **Evidence:** `bin/install_datasafe_service.sh:272` - `printf '%s\n' "${connectors[@]}"`.
  Under `set -u` on bash 4.3-, an empty array expansion raises "unbound variable".
- **Recommendation:** Use nounset-safe form: `printf '%s\n' ${connectors[@]+"${connectors[@]}"}`.

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID      | Severity | Area                | One-line                                                               |
|---------|----------|---------------------|------------------------------------------------------------------------|
| BASH-001 | High    | Strict mode         | `setup_error_handling` deferred; bootstrap phase unprotected          |
| BASH-002 | High    | Strict mode         | 2 scripts have no error protection at all                              |
| BASH-015 | High    | Temp files          | Credential-containing JSON uses predictable path, no EXIT trap        |
| BASH-003 | Medium  | Strict mode         | Libraries sourced without active `set -e`; ERR trap dormant           |
| BASH-004 | Medium  | Arithmetic          | Bare `((count++))` under `set -e` in ds_target_move.sh (fragile)      |
| BASH-007 | Medium  | Input safety        | OCI `--query` embeds unsanitized compartment name                     |
| BASH-008 | Medium  | Input safety        | jq filter embeds shell variables (2 instances in ds_target_register) |
| BASH-013 | Medium  | Robustness          | `generate_bundle_key` unbounded loop                                   |
| BASH-014 | Medium  | stderr handling     | `ds_refresh_target` uses `2>&1` bypassing `_oci_run_capture`          |
| BASH-016 | Medium  | Error handling      | `install_datasafe_service.sh` has no ERR trap or EXIT cleanup          |
| BASH-019 | Medium  | eval                | `resolve_*_to_vars` uses eval with OCI API response values             |
| BASH-021 | Medium  | Portability         | `mapfile` (bash 4.0) throughout; no bash 3.2 fallback                  |
| BASH-023 | Medium  | Installer           | Auto-regeneration mid-install without atomicity; `chown` failure masked |
| BASH-005 | Low     | Arithmetic          | `((frame++))` in stacktrace - context-dependent safety                 |
| BASH-006 | Low     | stderr routing      | Installer non-ERROR messages to stdout instead of stderr               |
| BASH-009 | Low     | Performance         | `echo|tr/jq/cut` subshell patterns in library functions                |
| BASH-018 | Low     | Locale              | No `LC_ALL=C` on `tr` lifecycle normalization                          |
| BASH-020 | Low     | Duplication         | `is_ocid` defined in 2 files; oci_helpers.sh version silently shadows  |
| BASH-024 | Low     | Array handling      | Empty array `${connectors[@]}` unsafe under `set -u` on bash 4.3-     |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** High: 3, Medium: 10, Low: 6
