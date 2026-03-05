
# Changelog

All notable changes to the OraDBA Data Safe Extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.19.1] - 2026-03-05

### Added

- `lib/oci_helpers.sh`: new `oci_lookup_pdb_connection()` function. Queries
  `oci db pluggable-database list`, finds a PDB by name (excluding TERMINATED),
  and parses the `pdb-default` connection string into `service|port`.

### Enhanced

- `bin/ds_target_update_service.sh`: template-based service naming via
  configurable brace-style placeholders (`{pdb}`, `{PDB}`, `{cdb}`, `{CDB}`,
  `{cluster}`, `{CLUSTER}`, `{sid}`, `{SID}`, `{domain}`) derived from the
  target display name. Default template `{pdb}_exa.{domain}` preserves
  backward-compatible output.
- `bin/ds_target_update_service.sh`: listener port update via `--port PORT`
  or `--update-port` (uses `LISTENER_PORT` from config). Off by default; opt-in.
- `bin/ds_target_update_service.sh`: root target (CDB$ROOT) handling — a
  separate `--root-service-template` is required; root targets are skipped
  with a warning when no template is configured.
- `bin/ds_target_update_service.sh`: `--from-oci` mode — automatically derives
  service name and listener port from the OCI PDB object's `pdb-default`
  connection string via `oci_lookup_pdb_connection()`.
- `bin/ds_target_update_service.sh`: `--no-service-update` flag to update
  port only; `--pdb-compartment COMP` for cross-compartment PDB lookup.
- `etc/datasafe.conf.example`: documented `SERVICE_TEMPLATE` and
  `ROOT_SERVICE_TEMPLATE` configuration variables.

### Fixed

- `bin/ds_target_update_service.sh`: OCI interactive prompt bypass — added
  `--force` to `target-database update` to prevent y/N hang.
- `bin/ds_target_update_service.sh`: `--wait-for-state` default changed from
  `SUBMITTED` (invalid) to `ACCEPTED` (first valid OCI work request state).
- `bin/ds_target_update_service.sh`: OCI `target-database update` uses PUT
  semantics — now fetches current `database-details` and merges changes into
  it before submitting, preserving required fields (`databaseType`,
  `infrastructureType`, `vmClusterId`, etc.).

## [0.19.0] - 2026-03-05

### Added

- `lib/oci_helpers.sh`: new `ds_filter_targets_by_tags()` function. Accepts a
  `{"data": [...]}` blob and a newline-separated list of tag expressions;
  returns only targets satisfying every expression (AND semantics). Wired into
  `ds_collect_targets_source()` (param 7) and `ds_collect_targets()` (param 5).
- `--tag-filter EXPR` flag added to all fourteen target operation scripts
  (`ds_target_list.sh`, `ds_target_activate.sh`, `ds_target_audit_trail.sh`,
  `ds_target_refresh.sh`, `ds_target_update_tags.sh`,
  `ds_target_update_connector.sh`, `ds_target_update_credentials.sh`,
  `ds_target_update_service.sh`, `ds_target_details.sh`, `ds_target_delete.sh`,
  `ds_target_move.sh`, `ds_tg_report.sh`, `ds_target_connector_summary.sh`,
  `ds_target_export.sh`). Multiple flags are AND-combined.
  Supports `key=value` (freeform), `key` (freeform presence),
  `namespace/key=value` (defined), `namespace/key` (defined presence).

## [0.18.3] - 2026-03-04

### Fixed

- `bin/ds_target_list.sh`: targets in DELETED or DELETING state were reported
  as `TARGET_UNEXPECTED_STATE` / `MEDIUM`. They are now reported as
  `TARGET_DELETING` / `LOW` with "No action required" — these targets are
  removed by OCI automatically and require no operator intervention.
- `bin/ds_target_list.sh`: DELETED and DELETING targets were counted in the
  per-SID root/PDB tallies used for `SID_DUPLICATE_ROOT` and `SID_MISSING_ROOT`
  checks. A SID with one active root and one deleted root was incorrectly
  flagged `SID_DUPLICATE_ROOT` / `HIGH`. DELETED and DELETING targets are now
  excluded from these counts.
- `bin/ds_target_register.sh`: registering a target whose display name matched
  an existing DELETED target was blocked with "Target already exists".
  `check_target_exists()` now ignores DELETED targets, allowing re-registration
  with the same name once the previous entry has been deleted.

### Added

- `bin/ds_database_prereqs.sh`: Database Vault detection per scope. Before
  running any DDL, the script queries `DBA_DV_STATUS` for the current container
  (ROOT or PDB). If DV is configured and enabled, a `WARN` is emitted with
  manual steps (DV_ACCMGR to create the user, DV_OWNER/SYS to grant privileges)
  and the scope is skipped. Other scopes in the same run are unaffected.

## [0.18.2] - 2026-03-03

### Fixed

- `bin/ds_connector_create.sh`: `--register-oradba` passed `--connector-home`
  to `ds_connector_register_oradba.sh` which does not accept that option,
  causing `[ERROR] Unknown option: --connector-home`. Argument removed.
- `bin/ds_connector_create.sh`: `--register-oradba` failed when the target
  environment was not yet present in `oradba_homes.conf`. `optional_register_oradba()`
  now checks for the entry and calls `oradba_homes.sh add --name ENV --path PATH
  --type datasafe --desc DISPLAY_NAME` to create it automatically before
  invoking `ds_connector_register_oradba.sh`.
- `bin/ds_target_connector_summary.sh`: on-premises connector targets were
  misclassified as "Cloud / Private Endpoint" because the OCI
  `target-database list` API omits `connection-option` for some targets. Added
  targeted post-grouping enrichment: after initial grouping, non-DELETED targets
  in the no-connector group are enriched via individual `target-database get`
  calls, the results are merged back, and targets are re-grouped. DELETED targets
  correctly remain in "Cloud / Private Endpoint".
- `bin/ds_target_connector_summary.sh`: spurious `[WARN] Ignoring unexpected
  arguments:` with empty content — whitespace-only strings from `parse_common_opts`
  are now rejected by stripping whitespace before the non-empty check.
- `bin/ds_target_update_connector.sh`: `distribute --targets LIST` silently
  ignored the target list and distributed the entire compartment instead.
  `do_distribute_mode()` now uses `ds_collect_targets` when `$TARGETS` is set,
  matching the behaviour of `do_set_mode()`.

### Added

- `bin/ds_target_connector_summary.sh`: `--no-enrich` flag skips the
  post-grouping per-target enrichment pass. Targets missing connector info in
  the list response appear as "Cloud / Private Endpoint". Useful for
  troubleshooting (identify affected targets fast) or when speed matters more
  than complete accuracy.
- `bin/ds_target_connector_summary.sh`: connector groups are now sorted
  alphabetically by connector name in all output formats (table, JSON, CSV).

### Changed

- `bin/ds_target_connector_summary.sh`: connector grouping uses OCID prefix
  filter (`startswith("ocid1.datasafeonpremconnector.")`) instead of membership
  in a pre-fetched connector list; also checks both `on-prem-connector-id` and
  `on-premise-connector-id` field name variants in `connection-option`.
- `bin/ds_target_connector_summary.sh`: no-connector group label changed from
  `"No Connector (Cloud)"` to `"Cloud / Private Endpoint"`.
- `bin/ds_target_connector_summary.sh`: removed `--enrich-connectors` and
  `--max-enrich-lookups` options (replaced by the targeted post-grouping
  enrichment approach).

## [0.18.1] - 2026-03-03

### Fixed

- `bin/ds_connector_create.sh`: bundle download (`generate-on-prem-connector-configuration`)
  failed immediately after OCI connector creation with HTTP 404
  "NotAuthorizedOrNotFound". Root cause: the connector is in `CREATING` state
  for a short period after the API call returns; the bundle download endpoint
  is not available until the connector transitions to `INACTIVE`. Fixed: added
  `wait_for_connector_not_creating()` which polls until the connector leaves
  `CREATING` (up to 2 minutes, 10 s intervals) before attempting the bundle
  download. Only runs in normal mode; HA mode skips it (connector already past
  `CREATING`).
- `bin/ds_connector_create.sh`: `setup.py install` failed with
  "the following arguments are required: --connector-port". Added
  `--connector-port PORT` flag (default: `1521`) and pass it to `setup.py install`
  via the `CONNECTOR_PORT_INPUT` environment variable in the non-interactive
  Python wrapper.

### Added

- `bin/ds_connector_create.sh`: `--connector-port PORT` option (default: `1521`)
  configures the port the connector service will listen on. Visible in the plan
  log and passed as `--connector-port` to `setup.py install`.

## [0.18.0] - 2026-03-03

### Added

- `bin/ds_connector_create.sh`: new script for end-to-end creation of an OCI
  Data Safe On-Premises Connector:
  1. Creates the connector object in OCI Data Safe
  2. Generates a bundle key (or reuses an existing one) and downloads the
     installation bundle
  3. Creates the local connector home directory
  4. Extracts the installation bundle
  5. Runs `setup.py install` with the bundle key to activate the connector
  6. Optionally polls until the connector reaches `ACTIVE` (configurable via
     `--wait-state`), then optionally registers the connector in
     `oradba_homes.conf` and/or installs it as a systemd service.
- `bin/ds_connector_create.sh`: added `--ha-node` flag for HA second-node
  installs. In HA mode the OCI connector create is skipped; the script looks up
  the existing connector by display name, reads the shared bundle key from
  `etc/<name>_pwd.b64`, and runs all local installation steps unchanged.
  `--force-new-bundle-key` is rejected in HA mode (would mismatch the deployed
  connector). Error messages guide the user when the connector or key file is
  missing.
- `lib/oci_helpers.sh`: extracted `is_valid_bundle_key()` and
  `generate_bundle_key()` from `ds_connector_update.sh` into the shared
  library so both update and create scripts use the same implementation.
  Added new `ds_create_connector()` wrapper for
  `oci data-safe on-prem-connector create`.

### Changed

- `bin/ds_connector_update.sh`: removed duplicate `is_valid_bundle_key()` and
  `generate_bundle_key()` functions — now sourced from `lib/oci_helpers.sh`.

### Fixed

- `bin/ds_target_delete.sh`: fixed explicit target OCID resolution to avoid
  stderr/log noise being captured into the resolved value. The script now
  validates the resolved value as an OCID before enqueueing deletion, preventing
  malformed OCI delete calls when target lookup emits mixed output.
- `scripts/build.sh`: fixed stale release-note accumulation on upgrade — the
  staged release note is now written as `doc/RELEASE_NOTES.md` (fixed name)
  instead of `doc/v${VERSION}.md`. With the old scheme each version added a new
  versioned file; after an upgrade both the old and new file were present, causing
  the `.extension.checksum` verification to fail on the unexpected file.

## [0.17.6] - 2026-03-02

### Fixed

- `bin/ds_target_update_tags.sh`: fixed two bugs that caused every OCI tag
  update to fail:
  - `build_tag_update_json()` wrapped the tag payload in an extra
    `{"defined-tags": {...}}` envelope. The `--defined-tags` CLI flag already
    implies that wrapper; the nested key was rejected by OCI CLI. Fixed: output
    only the namespace map `{"DBSec": {...}}` directly.
  - Missing `--force` on the `data-safe target-database update` call caused
    OCI CLI to prompt for interactive confirmation. Without a tty stdin the
    prompt received "invalid input" and the command exited 1 on every target.
    Fixed: `--force` now always included.
- `bin/ds_target_update_tags.sh`, `bin/ds_target_register.sh`: `DS_ENV_COMP_REGEX`
  set in `datasafe.conf` was silently ignored — Environment always resolved to
  `undef`. Root cause: the `${ENV_COMP_REGEX:=...}` default in the script
  preamble runs before `init_config` loads `datasafe.conf`, locking
  `ENV_COMP_REGEX` to an empty string. Fixed: `validate_inputs()` /
  `derive_tag_values()` now syncs `ENV_COMP_REGEX` from `DS_ENV_COMP_REGEX`
  after config load. CLI `--env-regex` still takes precedence.

### Added

- `bin/ds_target_update_tags.sh`: configurable, generic tag derivation:
  - **`ContainerType`** — auto-derived from target name suffix: `_CDBROOT` →
    `cdbroot`, otherwise `pdb`. No configuration required.
  - **`Environment`** — derived via a configurable regex applied to the
    compartment name. Capture group 1 is the environment value. Set
    `DS_ENV_COMP_REGEX` in `datasafe.conf` for your naming convention, or
    pass `--env-regex PATTERN` on the command line.
    Example: `'^cmp-.*-([^-]+)-projects$'` captures `prod` from
    `cmp-lzp-dbso-prod-projects`.
  - **`ContainerStage`** — auto-derived as `{type}-{env}` (e.g. `pdb-prod`,
    `cdbroot-test`); falls back to `undef` when `Environment` is `undef`.
    Override with `--stage VALUE`.
  - **`Classification`** — defaults to `undef`; set explicitly with
    `--class VALUE`.
- `etc/datasafe.conf.example`: added commented `DS_ENV_COMP_REGEX` example
  entry with usage notes and the customer pattern as illustration.
- `bin/ds_target_register.sh`: defined tags are now set on the target at
  registration time, using the same derivation logic as
  `ds_target_update_tags.sh`:
  - `ContainerType` auto-derived from the target display name suffix.
  - `Environment` derived from the compartment name via `DS_ENV_COMP_REGEX` /
    `--env-regex PATTERN`.
  - `ContainerStage` auto-derived as `{type}-{env}`; override with `--stage VALUE`.
  - `Classification` defaults to `undef`; set with `--class VALUE`.
  - New `--no-tags` flag skips all tag setting.

## [0.17.5] - 2026-03-02

### Added

- `bin/ds_target_register.sh`: added `--wait-state STATE` option. The default
  is now to return immediately after the registration API call succeeds
  (activation continues in the background). Pass `--wait-state ACTIVE` to
  restore the previous blocking behaviour (polls until the target reaches that
  lifecycle state or `FAILED`, with a 10-minute timeout). Any valid Data Safe
  target lifecycle state is accepted (`ACTIVE`, `NEEDS_ATTENTION`, etc.).
  `WAIT_STATE` is normalised to uppercase at parse time.

- All mutating scripts now expose a unified `--wait-state STATE` option
  (default: empty → return immediately after OCI API submission):
  - `bin/ds_target_refresh.sh`: replaced `--wait` / `--no-wait` with
    `--wait-state STATE`; passes `--wait-for-state "${WAIT_STATE}"` to
    `oci data-safe target-database refresh` only when non-empty.
  - `bin/ds_target_update_connector.sh`: replaced boolean `WAIT_FOR_COMPLETION`
    with `WAIT_STATE`; conditionally appends `--wait-for-state` to the OCI call.
  - `bin/ds_target_activate.sh`, `bin/ds_target_update_credentials.sh`,
    `bin/ds_target_update_service.sh`, `bin/ds_target_update_tags.sh`:
    renamed script option from `--wait-for-state` to `--wait-state` and
    variable from `WAIT_FOR_STATE` to `WAIT_STATE`; OCI CLI passthrough
    (`--wait-for-state "$WAIT_STATE"`) unchanged.
  - `bin/ds_target_delete.sh`: removed hardcoded `--wait-for-state SUCCEEDED`;
    added `--wait-state STATE` option. Default is now async (no blocking);
    pass `--wait-state SUCCEEDED` to restore the previous blocking behaviour.
  - `bin/ds_target_move.sh`: added `--wait-state STATE` option; `step_move_targets()`
    conditionally appends `--wait-for-state "${WAIT_STATE}"` to the
    `oci_exec data-safe target-database change-compartment` call.
  - `lib/oci_helpers.sh`: `ds_refresh_target()` updated to branch on `WAIT_STATE`
    (non-empty → blocking with state label in log; empty → async).

- `lib/oci_helpers.sh`: `check_oci_auth()` now logs the loaded `datasafe.conf`
  file paths (from `_DATASAFE_CONF_FILES`) and the resolved `DS_ROOT_COMP` value
  at DEBUG level, making configuration-discovery issues visible in debug output.
- `lib/common.sh`: added `_DATASAFE_CONF_FILES` global; `load_config()` appends
  each successfully loaded config file path to it so `check_oci_auth()` can emit
  a single summary log line.

- `lib/oci_helpers.sh`: new `oci_resolve_vmcluster_by_name()` — resolves a VM
  cluster display name to OCID **and** `compartment-id` in a single structured-
  search call (tries `VmCluster` then `CloudVmCluster`). Eliminates the previous
  two-step approach (search for OCID → `db vm-cluster get` for compartment).
- `bin/ds_target_register.sh`: `validate_inputs()` cluster-name branch now calls
  `oci_resolve_vmcluster_by_name()` directly, extracting both cluster OCID and
  compartment-id in one OCI round-trip. Falls back to `resolve_vm_cluster_ocid()`
  (Strategy 2: DB-list scan) only when structured search yields no result.
  `resolve_vm_cluster_ocid()` Strategy 1 simplified to use the new function,
  replacing the separate 1a/1b VmCluster/CloudVmCluster blocks.

- `scripts/build.sh`: added `doc/` to the release tarball; the latest release
  note (`doc/release_notes/v${VERSION}.md`) is staged as `doc/v${VERSION}.md`
  at the `doc/` root for the duration of the build and then removed. The
  `doc/release_notes/` subdirectory (including `archive/`) is excluded from
  both the tarball (`--exclude=doc/release_notes` in `tar`) and the
  `.extension.checksum` file (pruned by `find … -path '*/release_notes' -prune`).

- `bin/ds_target_audit_trail.sh`: added `--list`/`-l` subcommand for a
  read-only per-target audit trail status view — one row per target showing
  display name, trail lifecycle state (`COLLECTING`, `STOPPED`, `(no trail)`,
  etc.) and an advisory note (`ok`, `needs restart`, `missing`, …).
  Supports `-f/--format table|json|csv`, `--input-json FILE` (targets from
  `ds_target_list.sh --save-json`, avoiding a second OCI target fetch), and
  `--save-json FILE`. Compartment-id is extracted from the cached target payload
  so no extra `target-database get` call is needed when scanning by compartment
  or using `--input-json`; falls back to `target-database get` only for explicit
  OCID targets lacking compartment-id in the payload.
- `bin/ds_target_audit_trail.sh`: added `--input-json`/`--save-json` support
  to the existing start mode as well, so targets pre-selected by
  `ds_target_list.sh --save-json` can be fed directly to start without
  re-fetching from OCI.
- `tests/script_ds_target_audit_trail.bats`: four new `--list` tests covering
  help flags, `(no trail)` state, `COLLECTING` state, and CSV output header.

- `bin/ds_target_audit_trail.sh`: added `-A/--all` (select all targets from
  `DS_ROOT_COMP`) and `-r/--filter REGEX` (display-name regex filter) scope
  flags, using `ds_resolve_all_targets_scope`, `ds_validate_target_filter_regex`,
  and `ds_collect_targets_source` from `lib/oci_helpers.sh`.
- `bin/ds_target_details.sh`: added `-A/--all` and `-r/--filter REGEX` scope
  flags; target discovery in `do_work()` now uses `ds_collect_targets_source`
  for a single, unified collection path.
- `bin/ds_target_move.sh`: added `-A/--all` and `-r/--filter REGEX` scope
  flags; filter applied via `ds_filter_targets_json` in the compartment-scan
  branch of `preflight_checks()`.
- `bin/ds_target_delete.sh`: added `-r/--filter REGEX` scope flag; filter
  applied via `ds_filter_targets_json` in the compartment-scan branch of
  `validate_inputs()`.
- All four `ds_target_*` scripts now fall back to `DS_ROOT_COMP` when no
  `-T`/`-c`/`--all` is given (consistent with `ds_target_refresh.sh`), so
  `--filter REGEX` alone is a valid invocation when `DS_ROOT_COMP` is configured.
- `bin/ds_target_audit_trail.sh`: skip audit trails already in `COLLECTING`,
  `STARTING`, or `RESUMING` state instead of erroring; reported as skipped in
  the per-target and overall summary.
- `bin/ds_target_move.sh`: positional arguments (bare target names/OCIDs) are
  now appended to `TARGETS` instead of being silently stored in the now-removed
  `POSITIONAL` array.
- `tests/script_ds_target_audit_trail.bats`: new test file covering `--help`,
  mutual-exclusion of `--all`/`-c`/`-T`, and `--filter` regex validation.
- `tests/script_ds_target_delete.bats`: new test file covering `--help`,
  `--filter` regex validation, and `--stop-on-error` shift regression.
- `tests/script_ds_target_move.bats`: new test file covering `--help`,
  required `-D` flag, mutual-exclusion of `--all`/`-c`/`-T`, and `--filter`
  regex validation.
- `tests/script_ds_target_details.bats`: extended with `--all`/`--filter`
  mutual-exclusion tests and a filter-on-input-json test.

### Fixed

- `lib/oci_helpers.sh`: **security fix** — `ds_generate_connector_bundle()` passed
  `--password "$password"` inline to `oci_exec()`, which logged the full command at
  TRACE level and at ERROR level (always shown on failures), exposing the plaintext
  bundle encryption password. Added `_oci_redact_cmd()`: a one-pass sanitizer that
  replaces the value following `--password` in the command array with `****` before
  formatting for log output. Applied to all six log sites across `oci_exec()`,
  `oci_exec_ro()`, and `ds_refresh_target()`. The actual execution array is unchanged;
  only the string used in log messages is sanitised.

- `lib/oci_helpers.sh`: `check_oci_auth()` now logs the active OCI config file,
  profile, and region at DEBUG level before the authentication check, making
  it easy to spot wrong-profile issues in debug output.
- `bin/ds_target_register.sh`: fixed subshell variable propagation bug in
  `validate_inputs()` — the cluster-name branch now calls
  `oci_resolve_vmcluster_by_name()` directly so that `CLUSTER_OCID` and
  `derived_compartment` are assigned in the parent shell. The previous code
  called `resolve_vm_cluster_ocid()` inside `$(...)`, making any global set
  inside that subshell invisible to the parent; `derived_compartment` was
  always empty, causing the unnecessary host-derivation path to run and
  potentially overwrite the correct cluster compartment.
- `bin/ds_target_register.sh`: connector lookup no longer silently falls back
  to the target database compartment when `DS_ROOT_COMP`/`DS_CONNECTOR_COMP`
  are not set. The fallback now emits two `[WARN]` lines directing the user to
  configure the missing variable. The `die` message on connector-not-found now
  includes the searched compartment OCID for easier diagnosis.
- `lib/oci_helpers.sh`: `oci_exec()` and `oci_exec_ro()` now log the OCI command
  using `$(printf '%q ' "${cmd[@]}")` instead of `${cmd[*]}`. The old form joined
  array elements with spaces and stripped quoting from multi-word arguments (e.g.
  `--query-text "query VmCluster …"`), making copy-pasted trace output invalid.
  The new form shell-escapes each element so the logged command can be run as-is.
- `bin/ds_target_register.sh`: PDB registration on ExaCC no longer fails when
  `pluggableDatabaseId` cannot be resolved. For ExaCC targets (where
  `CLUSTER_OCID` is set), a failed PDB OCID lookup is now a warning rather than
  a fatal error — the Data Safe API accepts the registration using
  `vmClusterId` + `serviceName` alone, matching the legacy behaviour confirmed
  in `register_datasafe_pdb_v1.0.0.sh`. Non-ExaCC registrations still require
  and enforce a resolved pluggable DB OCID.
- `bin/ds_target_audit_trail.sh`: fixed `start_audit_trails()` — the correct
  flow is: list trails via `audit-trail list --compartment-id <ocid> --target-id
  <ocid> --all` (response is `AuditTrailCollection`: `{"data":{"items":[...]}}`,
  jq query `(.data.items // .data)[]?.id`), then start each by its OCID via
  `audit-trail start --audit-trail-id`. Removed invalid CLI parameters
  (`--is-auto-queries-enabled`, `--update-last-archive-timestamp`,
  `--audit-trail-type`, `--collection-frequency`) from the start call; valid
  parameters are `--audit-collection-start-time` and `--is-auto-purge-enabled`.
- `bin/ds_target_audit_trail.sh`: fixed `--audit-collection-start-time` default
  value `"now"` (not a valid RFC3339 timestamp); converted at runtime to
  `date -u +"%Y-%m-%dT%H:%M:%SZ"` when the default is used.
- `bin/ds_target_audit_trail.sh`: fixed inverted argument order in two `die`
  calls (`die 1 "msg"` → `die "msg" 1`) that caused "numeric argument required"
  shell errors on failure.
- `bin/ds_target_audit_trail.sh`: removed `2>&1` redirect on `oci_exec` calls
  so that `log_error` / `log_trace` messages on OCI failures are visible
  (previously suppressed to `/dev/null`).
- `bin/ds_target_delete.sh`: fixed missing `shift` after `--stop-on-error`
  flag, which caused the next argument to be silently consumed.
- `bin/ds_target_details.sh`: removed dead `list_targets_in_compartment()`
  function, which was no longer called after the refactor to
  `ds_collect_targets_source`.
- `bin/ds_target_details.sh`: fixed `--filter` not applied when using
  `--input-json`; the 4th arg to `ds_collect_targets_source` was `""` instead
  of `"$TARGET_FILTER"` in the input-json branch of `do_work()`.
- `tests/script_ds_target_audit_trail.bats`: fixed "accepts valid --filter
  regex with -T" test — replaced the target name `some-target` with a target
  OCID (`ocid1.datasafetargetdatabase.oc1..t1`) to avoid the name-resolution
  OCI call that requires `DS_ROOT_COMP` in the test environment; updated mock
  to return `some-target` as `display-name` (so filter `some` still matches).

- `lib/oci_helpers.sh`: demoted raw OCI CLI command lines and error output from
  `log_debug` to `log_trace` in `oci_exec`, `oci_exec_ro`, `ds_refresh_target`,
  and `ds_update_target_tags`. Running with `--debug` now shows only semantic
  decisions; `--trace` reveals raw OCI command details.
- `bin/ds_target_register.sh`: demoted "Validating inputs…" entry log and
  JSON payload dump lines from `log_debug` to `log_trace` for the same reason.
- `lib/oci_helpers.sh`: extracted three general-purpose OCI helpers for DbNode
  and VM-cluster lookups out of the script and into the shared library:
  - `oci_resolve_dbnode_by_host(host)` — single structured-search call returning
    raw DbNode JSON for further field extraction.
  - `oci_resolve_compartment_by_dbnode_name(host)` — resolve compartment OCID
    from DbNode display name (hostname).
  - `oci_resolve_vm_cluster_compartment(ocid)` — resolve compartment OCID from
    VM-cluster OCID with type dispatch (`vmcluster` / `cloudvmcluster`) and
    fallback to generic search.
- `bin/ds_target_register.sh`: `resolve_compartment_from_host()` and
  `resolve_vm_cluster_compartment_ocid()` are now thin delegation wrappers
  for the corresponding library functions above.
- `bin/ds_target_list.sh`: removed three private functions that duplicated
  existing library equivalents:
  - `apply_target_filter()` → replaced with `ds_filter_targets_json()` from
    `lib/oci_helpers.sh` (2 call sites; filter is now passed as a parameter
    instead of read from a global).
  - `load_json_selection()` → replaced with `ds_load_targets_json_file()` from
    `lib/oci_helpers.sh`.
  - `save_json_selection()` → replaced with `ds_save_targets_json_file()` from
    `lib/oci_helpers.sh`.
- `lib/oci_helpers.sh`: extracted five additional general-purpose helpers into
  the shared library:
  - `ds_is_updatable_lifecycle_state(state)` — returns 0 when a target's
    lifecycle state (`ACTIVE`, `NEEDS_ATTENTION`) permits credential updates.
  - `ds_is_cdb_root_target(name, ocid)` — detects CDB$ROOT scope via name
    pattern (`_CDBROOT`) and freeform tags (`DBSec.Container`,
    `DBSec.ContainerType`).
  - `ds_build_connector_map(compartment_ocid, use_subtree)` — populates the
    caller's `CONNECTOR_MAP` associative array (OCID → name) using
    `oci_exec_ro`; optional subtree flag.
  - `ds_write_cred_json_file(path, user, pass)` — writes a `{userName, password}`
    JSON credential file via `jq -n`.
  - `ds_resolve_user_for_scope(scope, base_user, prefix)` — strips or prepends
    `COMMON_USER_PREFIX` based on scope label (`PDB` / `ROOT`).
- `bin/ds_target_update_credentials.sh`: `is_updatable_lifecycle_state()` and
  the `jq -n` call in `create_temp_cred_json()` now delegate to the library.
- `bin/ds_target_activate.sh`: `is_cdb_root()`, `resolve_ds_user()`, and the
  `jq -n` calls in `create_temp_cred_json()` now delegate to the library.
- `bin/ds_target_details.sh`: `build_connector_map()` now delegates to
  `ds_build_connector_map()` in the library.
- `bin/ds_target_export.sh`: `build_connector_map()` now delegates to
  `ds_build_connector_map()` in the library.

### Fixed (registration and cluster resolution)

- `bin/ds_target_register.sh`: Data Safe registration payload for
  cloud-at-customer now resolves and includes required resource identifiers
  (`vmClusterId` for root scope and `pluggableDatabaseId` for PDB scope),
  fixing OCI `InvalidParameter` errors such as
  "The vm cluster id or pluggable database id cannot be null.".
- `bin/ds_target_register.sh`: improved automatic compartment derivation from
  host/cluster by trying configured search scopes (`DS_REGISTER_COMPARTMENT`
  and `DS_ROOT_COMP`) instead of relying on a single root-compartment path.
- `bin/ds_target_register.sh`: resolution order now follows legacy behavior by
  resolving VM cluster first (from `--cluster` or `--host`) and deriving
  compartment from the resolved VM cluster before falling back to configured
  defaults.
- `bin/ds_target_register.sh`: host-based compartment and cluster-OCID
  derivation now issues a single `query DbNode resources where displayName =
  '...'` OCI call and extracts both the `compartment-id` and `vmClusterId`
  from the result, eliminating a redundant second DbNode search.
- `bin/ds_target_register.sh`: registration no longer uses `--wait-for-state`
  (which mixed OCI CLI progress output into the captured JSON result, causing
  jq parse failures). Target creation is submitted asynchronously and the
  script polls `ds_list_targets` every 15 s until the target reaches `ACTIVE`
  or `FAILED` state (max 10 min).
- `bin/ds_target_register.sh`: `credentials.password` is now redacted as
  `"****"` in all DEBUG- and TRACE-level JSON payload dumps, preventing
  plaintext passwords from appearing in logs.
- `bin/ds_target_register.sh`: VM cluster discovery now supports both OCI DB
  resource families (`cloud-vm-cluster` and `vm-cluster`) for `--cluster`
  name/OCID resolution and compartment lookup, addressing environments where
  Exadata resources are exposed as `vmcluster` rather than `cloudvmcluster`.
- `bin/ds_target_register.sh`: cluster and compartment OCI lookups now call
  `oci_exec_ro search resource structured-search` directly instead of routing
  through `oci_structured_search_query`, ensuring debug/trace messages from
  `oci_exec_ro` are visible and avoiding a missing-function error when only the
  script is deployed without an updated `lib/oci_helpers.sh`.
- `lib/oci_helpers.sh` / `bin/ds_target_register.sh`: introduced a simplified,
  legacy-style structured-search resolver path (`oci_resolve_ocid_by_name`,
  `oci_get_compartment_of_ocid`) and switched registration cluster/compartment
  lookup to this model, avoiding fragile `db node list` / cluster list flows
  that require additional parameters in some OCI CLI versions.

## [0.17.3] - 2026-02-26

### Changed

### Fixed

- `bin/ds_target_refresh.sh` / `lib/oci_helpers.sh`: refresh calls that hit OCI
  "operation already in progress" conflicts are now classified before generic
  OCI failure logging, so expected skip cases no longer emit misleading
  `ERROR` messages and are reported as warning-level skips only.
- `bin/ds_target_list.sh`: fixed `--mode problems|health --issue-view details`
  table alignment when issue labels are long by using a wider fixed `Issue`
  column and truncating overflow labels with ellipsis.
- `bin/ds_target_register.sh`: fixed registration create wait handling by using
  valid OCI Data Safe operation states (`SUCCEEDED`/`FAILED`) instead of
  invalid target lifecycle state `ACTIVE`, and corrected fatal error exit
  invocation so failures return code `2` without secondary shell errors.

## [0.17.2] - 2026-02-23

### Changed

- Updated default logging behavior to start in verbose (`INFO`) mode when no
  explicit logging flag is provided for operational scripts:
  - `bin/ds_target_refresh.sh`
  - `bin/ds_target_update_service.sh`
  - `bin/ds_target_register.sh`
  - `bin/ds_target_update_connector.sh`
  - `bin/ds_target_update_tags.sh`
  - `bin/ds_target_delete.sh`
  - `bin/ds_target_activate.sh`
  - `bin/ds_connector_update.sh`
  - `bin/ds_target_audit_trail.sh`
- Preserved explicit logging flag precedence (`--quiet`, `--verbose`, `--debug`)
  so user-selected verbosity continues to override script defaults.

## [0.17.1] - 2026-02-23

### Changed

- Added backward-compatible short mode aliases in `bin/ds_target_list.sh`:
  `-C` (count), `-H` (health), `-P` (problems), and `-R` (report), while
  preserving existing long options and `--mode` usage.
- Aligned the `Delta vs previous run` report section in `bin/ds_target_list.sh`
  using fixed-width labels for cleaner and more consistent terminal output.

## [0.17.0] - 2026-02-23

### Changed

- `bin/ds_target_list.sh` mode model was simplified and normalized:
  `--mode details|count|overview|health|problems|report` with direct aliases
  `--details`, `--count`, `--overview`, `--health`, `--problems`, `--report`.
- `bin/ds_target_list.sh` troubleshooting options were unified to:
  `--issue-view`, `--issue`, `--action`, and `--no-action`.
- `bin/ds_target_list.sh` overview toggles were streamlined to:
  `--status`, `--no-status`, `--no-members`,
  `--truncate-members`, and `--no-truncate-members`.
- `bin/ds_target_list.sh` issue-summary table output was consolidated so
  `--mode health`, `--mode problems`, and `--mode report` share the same
  report-style columns (`Issue`, `Severity`, `Count`, `SIDs`, `SID %`,
  `Suggested Action`).
- `--mode problems` now intentionally scopes to actionable runtime issues
  (`TARGET_NEEDS_ATTENTION*`, `TARGET_INACTIVE`, `TARGET_UNEXPECTED_STATE`)
  and still supports drill-down via `--issue-view details`.
- Report-generation processing in `bin/ds_target_list.sh` now performs fewer
  repeated `jq` scans by consolidating issue analytics and report metadata
  extraction paths.
- Removed dead helper functions in `bin/ds_target_list.sh` that were no longer
  part of the active execution path.
- Logging defaults were tightened to be quiet by default across scripts:
  default output now suppresses `INFO`/`DEBUG`/`TRACE` logs and only shows
  `WARN`/`ERROR`/`FATAL`.
- Updated common logging flag semantics in `lib/common.sh`:
  - `--quiet` keeps `WARN`/`ERROR`/`FATAL` only,
  - `--verbose` enables `INFO` (without `DEBUG`/`TRACE`),
  - `--debug` enables full trace output (`TRACE` + `DEBUG` + higher levels).
- `parse_common_opts` now explicitly resets per-invocation baseline log level
  to quiet (`WARN`) before applying CLI log flags, preventing environment or
  config carry-over from re-enabling noisy logs unexpectedly.
- Added reusable target-source helpers in `lib/oci_helpers.sh` for
  normalized JSON load/save and source collection (`ds_collect_targets_source`)
  supporting OCI and local payload workflows.
- Added Phase 1 `--input-json` / `--save-json` support to read-only scripts:
  `bin/ds_tg_report.sh`, `bin/ds_find_untagged_targets.sh`, and
  `bin/ds_target_connector_summary.sh`.
- Added Phase 2 `--input-json` / `--save-json` support to
  `bin/ds_target_export.sh` and `bin/ds_target_details.sh`, including
  local payload processing paths for offline detail/export workflows.
- Started Phase 3 safeguard rollout for mutating scripts by adding
  `--input-json` / `--save-json` support to `bin/ds_target_refresh.sh` and
  `bin/ds_target_update_tags.sh` with fail-closed apply behavior:
  offline apply is blocked by default and requires
  `--allow-stale-selection`, with optional freshness enforcement via
  `--max-snapshot-age`.
- Extended Phase 3 safeguard rollout to
  `bin/ds_target_update_credentials.sh` and
  `bin/ds_target_update_service.sh` with the same fail-closed replay model
  (`--allow-stale-selection` + `--max-snapshot-age`) for offline apply paths.

### Documentation

- Updated `doc/index.md` and `doc/quickref.md` examples and flag descriptions
  to reflect the current `ds_target_list.sh` mode aliases/options
  (`health` mode naming, overview flags, report aliases, and logging behavior).
- Updated `doc/release_notes/v0.17.0.md` to reflect the current consolidated
  `ds_target_list.sh` CLI and issue-summary output model.
- Updated script help and tests for `--input-json` / `--save-json` coverage in
  Phase 1 read-only target analysis commands.
- Added script help, quick reference examples, and targeted tests for Phase 2
  export/details input-json and save-json workflows.
- Added safeguard-focused help/docs/tests for Phase 3 mutating-script replay
  (`refresh`, `update_tags`) including blocked-by-default apply from
  `--input-json` snapshots.
- Added safeguard-focused help/docs/tests for Phase 3 mutating-script replay
  in `update_credentials` and `update_service`, including blocked-by-default
  apply from `--input-json` snapshots.

### Fixed

- `bin/ds_target_refresh.sh` now treats OCI refresh `Conflict` responses with
  "operation already in progress" as non-fatal skips so bulk refresh runs
  continue and report skipped targets instead of aborting.

---

## Older Versions (< 0.17.0)

Versions prior to 0.17.0 have been archived.
See [doc/release_notes/archive/CHANGELOG_archive.md](doc/release_notes/archive/CHANGELOG_archive.md).
