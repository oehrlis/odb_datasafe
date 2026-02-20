# Target Troubleshooting Guide

This guide describes how to troubleshoot target landscape inconsistencies using
`bin/ds_target_list.sh --health-overview`.

Health checks always run on the selected scope (`--all`, `-c`, `-T`, `-r`,
`-L`) and process results locally.

## Health Overview

```bash
# Health overview for default scope
bin/ds_target_list.sh --health-overview

# Health overview for filtered scope
bin/ds_target_list.sh --health-overview -r "b14_"

# Include issue drill-down details
bin/ds_target_list.sh --health-overview --health-details

# Machine-readable output
bin/ds_target_list.sh --health-overview -f json
bin/ds_target_list.sh --health-overview -f csv
```

## Implemented v1 Checks

- SID has PDB targets but no CDB root (`SID_MISSING_ROOT`)
- SID has multiple CDB roots (`SID_DUPLICATE_ROOT`)
- SID has CDB root but no PDB targets (`SID_ROOT_WITHOUT_PDB`)
- Target in `NEEDS_ATTENTION` with lifecycle reason (`TARGET_NEEDS_ATTENTION`)
- Target in `INACTIVE` state (`TARGET_INACTIVE`)
- Target in state outside normal states (`TARGET_UNEXPECTED_STATE`)
- Target name does not match configured naming standard (`TARGET_NAMING_NONSTANDARD`)

## Needs-Attention Classification (v2)

`--health-overview` now classifies `NEEDS_ATTENTION` reasons into actionable
categories to make remediation planning easier:

- `TARGET_NEEDS_ATTENTION_ACCOUNT_LOCKED`
  - Example: `ORA-28000`, `account is locked`
  - Action: unlock/reset DB account, then update Data Safe credentials and refresh.
- `TARGET_NEEDS_ATTENTION_CREDENTIALS`
  - Example: `ORA-01017`, `invalid username/password`, `account has expired`
  - Action: reset DB password if needed, update credentials in Data Safe, refresh.
- `TARGET_NEEDS_ATTENTION_CONNECTIVITY`
  - Example: login timeout / connect failures
  - Action: check connector, CMAN/network/listener/service, then refresh.
- `TARGET_NEEDS_ATTENTION_FETCH_DETAILS`
  - Example: `Failed to fetch connection details for the target database`
  - Action: verify connect details + connector/network, then refresh.
- `TARGET_NEEDS_ATTENTION_OTHER`
  - Fallback for unmatched reasons.

Default normal states: `ACTIVE,UPDATING` (configurable via
`HEALTH_NORMAL_STATES`).

## Naming Standard Checks

Default expected target naming pattern:

```text
<cluster>_<oracle_sid>_<cdb/pdb>
```

For environments with different naming schemes, tune parser settings in
`etc/datasafe.conf`:

- `DS_TARGET_NAME_REGEX`
- `DS_TARGET_NAME_SEPARATOR`
- `DS_TARGET_NAME_SID_REGEX`
- `DS_TARGET_NAME_CDBROOT_REGEX`

## Suggested Actions (v1)

- Missing root: register/refresh the CDB root target for the SID.
- Duplicate roots: review and keep a single valid root target.
- Needs attention: inspect lifecycle-details, then run targeted
  refresh/credentials/connector updates.
- Inactive: activate target(s) using `bin/ds_target_activate.sh`.
- Unexpected state: wait/poll state transition and retry affected operation.
- Naming non-standard: align naming or configure parser regex settings.
