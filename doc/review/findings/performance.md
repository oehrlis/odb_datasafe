# Performance Findings - odb_datasafe v0.20.4

**Scope:** lib/oci_helpers.sh, lib/common.sh, bin/ds_target_list.sh,
bin/ds_target_connector_summary.sh, bin/datasafe_env.sh

**Context:** odb_datasafe is a CLI tool wrapping OCI CLI. Performance is dominated by OCI API
call latency (2-8s each). Script-level micro-optimizations are secondary. This review flags
patterns that either multiply OCI API calls O(N) or add >50ms startup overhead.

---

## Findings

### PERF-001 - Per-target OCI GET during enrichment loop - default-on, O(N) serial

- **Severity:** Critical
- **Evidence:** `bin/ds_target_connector_summary.sh:746-758` - `ENRICH_MISSING=true` (default)
  fires one `oci data-safe target-database get` per non-DELETED target lacking connector info.
- **Cost:** Each OCI API call takes 2-8s over WAN. 10 targets = 20-80s added latency. This is
  always active unless `--no-enrich` is passed.
- **Recommendation:** Default `ENRICH_MISSING` to `false`; require explicit `--enrich` opt-in
  for the expensive enrichment. Or batch collect OCIDs and issue parallel background calls
  with `wait`.

---

### PERF-002 - `ds_resolve_target_name` OCI GET in bulk mutation functions - one extra call per target

- **Severity:** High
- **Evidence:** `lib/oci_helpers.sh:1634` (`ds_refresh_target`), `:1706` (`ds_update_target_tags`),
  `:1748` (`ds_update_target_service`), `:1788` (`ds_delete_target`);
  `bin/ds_target_activate.sh:433` (`activate_single_target`). Each resolves the target name
  (one OCI GET) even though callers already have the name from the initial list response.
- **Cost:** For a 50-target bulk refresh: 50 avoidable OCI GET calls at 2-8s each = 100-400s
  serial overhead before the first actual refresh fires.
- **Recommendation:** Accept optional `target_name` parameter; fall back to OCI GET only when
  parameter is empty.

---

### PERF-003 - `oci_resolve_compartment_ocid` called 3x on same compartment; no result cache

- **Severity:** High
- **Evidence:** `bin/ds_target_connector_summary.sh:278,284,677` - three calls to
  `oci_resolve_compartment_ocid` for the same compartment. Against a compartment name (not OCID),
  this issues `oci iam compartment list --all --compartment-id-in-subtree true` - potentially
  the most expensive single IAM call.
- **Cost:** ~2-5s per call against a name = ~6-15s avoidable latency per script run.
- **Recommendation:** Add a `declare -A _COMP_OCID_BY_NAME_CACHE` cache in
  `oci_resolve_compartment_ocid`, parallel to the existing `_DS_ROOT_COMP_OCID_CACHE` pattern.

---

### PERF-004 - `ds_is_cdb_root_target` slow path fires one OCI GET per target not matching name pattern

- **Severity:** Medium
- **Evidence:** `lib/oci_helpers.sh:1507-1530` - called in `bin/ds_target_activate.sh:442`.
  For environments without the `_CDBROOT` naming convention, fires one OCI GET per target.
- **Recommendation:** Accept pre-fetched `freeform-tags` JSON from the list response as an
  optional parameter. Slow path only fires when no pre-fetched data is available.

---

### PERF-005 - `show_summary_table` spawns 5-8 `echo | jq` subshells per connector per iteration

- **Severity:** High
- **Evidence:** `bin/ds_target_connector_summary.sh:407-459` - per connector: 3 subshells
  for connector_count/conn_name/conn_id + 3-5 for state data = ~8 per connector.
- **Cost:** 10 connectors × 3 states = ~120 subshell forks ≈ 3.6s on macOS, entirely for
  display of already-in-memory JSON.
- **Recommendation:** Replace nested bash loops with a single jq invocation that renders all
  rows in one pass: `echo "$grouped_json" | jq -r '.[] | ... | @tsv'` piped to `while read`.

---

### PERF-006 - `show_detailed_table` spawns 3 `echo | jq` subshells per connector in outer loop

- **Severity:** Medium
- **Evidence:** `bin/ds_target_connector_summary.sh:535-592` - 3 subshells per connector
  (connector_count, conn_name/conn_id, target_count) + one per target group.
- **Cost:** 10 connectors ≈ 30 subshell forks ≈ 900ms on macOS.
- **Recommendation:** Same single-pass jq approach as PERF-005.

---

### PERF-007 - `show_count_mode` uses `sort | uniq -c | sort -rn` pipeline on in-memory JSON

- **Severity:** Low
- **Evidence:** `bin/ds_target_list.sh:1980` - `sort | uniq -c | sort -rn` (3 external processes)
  for counting lifecycle states that jq can aggregate natively.
- **Recommendation:** Replace with jq `group_by`/`length` pipeline, eliminating 3 external
  process forks.

---

### PERF-008 - Every bin script uses a 3-process pipeline to extract SCRIPT_VERSION at startup

- **Severity:** Medium
- **Evidence:** `bin/ds_target_list.sh:25`, `bin/ds_target_connector_summary.sh:26` and ~21
  additional bin scripts - all use `grep | awk | tr` (3 processes) to extract version from
  `.extension`.
- **Cost:** 3 subshell forks per script invocation ≈ 90ms one-time init. Compounds when scripts
  are chained.
- **Recommendation:** Replace with `read -r SCRIPT_VERSION < "${SCRIPT_DIR}/../VERSION"` (0
  external processes).

---

### PERF-009 - `log()` spawns two subshells per call regardless of whether output is suppressed

- **Severity:** Medium
- **Evidence:** `lib/common.sh:133-135` - `level_num=$(_log_level_num "$level")` and
  `current_num=$(_log_level_num "$LOG_LEVEL")` are called via subshell on every `log*` invocation,
  even for calls that are filtered out.
- **Cost:** 2 forks × 50+ log calls per INFO-level run = ~100 forks ≈ 3s on macOS.
- **Recommendation:** Pre-compute numeric log level at `parse_common_opts` time; compare
  integers directly in `log()` with an inline `case` statement, eliminating both subshells.

---

### PERF-010 - `_ds_cache_mtime` runs stat twice: probe + value; exact duplicate exists

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:77-88` (`_ds_cache_mtime`) and `:1074-1085`
  (`_ds_file_mtime`) are byte-for-byte identical; both use probe-then-capture pattern.
- **Recommendation:** Delete `_ds_cache_mtime`; repoint caller at `_ds_file_mtime`. Use
  `if mtime=$(stat -f '%m' "$file" 2>/dev/null); then` to capture and check in one step.

---

### PERF-011 - `ds_list_targets` uses `echo | tr | tr` pipeline for string normalization

- **Severity:** Low
- **Evidence:** `lib/oci_helpers.sh:771` - `$(echo "$lifecycle_input" | tr '[:lower:]' '[:upper:]' | tr -d ' ')` (2 forks).
- **Recommendation:** `lifecycle_norm="${lifecycle_input^^}"; lifecycle_norm="${lifecycle_norm// /}"` (bash 4+, 0 forks), or single `tr` via `<<<`.

---

### PERF-012 - Bulk target operations are strictly serial - no bounded parallelism

- **Severity:** Medium
- **Evidence:** `bin/ds_target_refresh.sh:375-387`; `bin/ds_target_activate.sh:524-533` -
  sequential OCI mutating calls over N targets.
- **Cost:** N × (2-10s) for a 50-target bulk operation = 100-500s serial latency.
- **Recommendation:** For `--mode async`, implement bounded parallelism: spawn up to configurable
  `MAX_PARALLEL` background jobs and `wait` for completion, collecting exit codes into a results
  array.

---

## Positive Observations

- Target list caching (`_DS_TARGET_CACHE_JSON` memory + file-backed TTL) is correctly implemented;
  avoids repeated `data-safe target-database list` calls.
- `check_oci_cli_auth` cached in `_OCI_CLI_AUTH_CHECKED` - correct.
- `get_root_compartment_ocid` and `get_connector_compartment_ocid` have memory caches - correct.
- All library files use guard variables to prevent double-sourcing - correct.
- Subshell anti-patterns inside loops already addressed in commit `13a0ecd` (2026-05-02).

---

## Summary Table

<!-- markdownlint-disable MD013 MD060 -->
| ID      | Severity | Pattern              | One-line                                                             |
|---------|----------|----------------------|----------------------------------------------------------------------|
| PERF-001 | Critical | O(N) OCI calls       | Per-target OCI GET in enrichment loop, default-on                    |
| PERF-002 | High     | O(N) OCI calls       | `ds_resolve_target_name` GET in bulk functions - 1 extra call/target |
| PERF-003 | High     | O(N) OCI calls       | `oci_resolve_compartment_ocid` called 3x without caching             |
| PERF-005 | High     | Subshell fan-out     | 8+ `echo|jq` subshells per connector in summary display loop         |
| PERF-004 | Medium   | O(N) OCI calls       | `ds_is_cdb_root_target` slow path fires per-target OCI GET           |
| PERF-006 | Medium   | Subshell fan-out     | 3 `echo|jq` subshells per connector in detailed table                |
| PERF-008 | Medium   | Init overhead        | 3-process pipeline for SCRIPT_VERSION at every startup               |
| PERF-009 | Medium   | Logging overhead     | 2 subshells per `log*` call even when filtered                       |
| PERF-012 | Medium   | Parallelism          | Bulk target operations strictly serial, no bounded parallelism       |
| PERF-007 | Low      | Subshell fan-out     | `sort|uniq-c|sort` on in-memory data for count mode                  |
| PERF-010 | Low      | Duplicate function   | `_ds_cache_mtime` identical to `_ds_file_mtime` in same file         |
| PERF-011 | Low      | Subshell fan-out     | `echo|tr|tr` for string normalization in `ds_list_targets`           |
<!-- markdownlint-enable MD013 MD060 -->

**Severity counts:** Critical: 1, High: 3, Medium: 5, Low: 3
