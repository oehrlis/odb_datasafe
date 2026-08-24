# Audit Reconcile and Trail Reporting

Guide for the Data Safe audit rollout: how to bring every target into audit
collection in controlled waves, and how to verify the result before releasing
the next wave.

Scripts covered:

- [`bin/ds_audit_reconcile.sh`](../bin/ds_audit_reconcile.sh) - reconcile run
- [`bin/ds_trail_report.sh`](../bin/ds_trail_report.sh) - trail state report

## The problem

A Data Safe tenancy at scale drifts in three ways:

1. Targets are registered without a `DBSec.ContainerStage` tag. Target groups
   are formed from exactly that defined tag, so an untagged target belongs to no
   group and receives no security policy.
2. Data Safe has no audit trail object for a target. That is not a state you can
   fix by starting something - the trail has to be discovered first.
3. An audit trail exists but was never started, so no audit record ever reaches
   the repository and nothing flows on to the SIEM.

`ds_audit_reconcile.sh` closes all three gaps in one idempotent run.

## Fixed policy

Three things are decided and are not configurable away:

| Policy | Why |
| --- | --- |
| Collection starts at `--start-time` (default `now`) | No historic audit data is ever backfilled. Collection applies from the moment it is switched on. |
| `--is-auto-purge-enabled true` on every start | Without it the audit trail inside the database grows without bound. |
| A target without `DBSec.ContainerStage` is a defect | It is fixed, not tolerated. An untagged target is invisible to every target group. |

`NEEDS_ATTENTION` is deliberately outside the automation. It is reported and
left alone, because the cause is per-target and needs a human look.

## Trail state: two fields, not one

An OCI audit trail carries two independent state fields:

| Field | Values | Meaning |
| --- | --- | --- |
| `lifecycle-state` | `ACTIVE`, `NEEDS_ATTENTION`, `FAILED`, `DELETING`, ... | Is the trail object healthy? |
| `status` | `NOT_STARTED`, `COLLECTING`, `IDLE`, `STOPPED`, `STOPPED_NEEDS_ATTN`, ... | Is collection running? |

Both scripts collapse the two into one reported state:

| Reported state | Derived from |
| --- | --- |
| `COLLECTING`, `IDLE`, `STARTING`, `RESUMING`, `RECOVERING`, `RETRYING` | `status`, collection is running |
| `NOT_STARTED` | `status`, the trail exists but was never started |
| `STOPPED`, `INACTIVE` | collection was stopped |
| `NEEDS_ATTENTION` | `lifecycle-state` `NEEDS_ATTENTION`/`FAILED`, or `status` `STOPPED_NEEDS_ATTN`/`STOPPED_FAILED` |
| `NO_TRAIL` | not an OCI state - the target has no trail object at all |

Reading `lifecycle-state` alone can never surface `NOT_STARTED`, which is what
most of a fresh tenancy looks like.

## What the reconcile run does

```text
1. Collect targets, audit trails and audit profiles   3 bulk calls
2. Targets without DBSec.ContainerStage               report, then tag
3. Targets without a trail object                     report, then discover
4. Trails in NOT_STARTED                              report, then start
5. Trails in NEEDS_ATTENTION                          report only
6. Reconcile report
```

The run delegates rather than reimplements:

| Step | Delegate |
| --- | --- |
| Tagging | `ds_target_update_tags.sh --apply` |
| Discovery | `oci data-safe audit-profile discover-audit-trails` via `ds_lib.sh` |
| Start | `ds_target_audit_trail.sh --start-time now --auto-purge true` |

### Why discovery, not create

There is no `audit-trail create` operation. Data Safe discovers trails from the
target database, and the audit profile is the handle for that. Discovery is
asynchronous: the trail object appears after the work request completes, so it
is started by a later reconcile run, not the current one. That is the reason
the run is designed to be repeated.

### Tag derivation

`ds_target_update_tags.sh` derives the value, this script does not:

- Environment: capture group 1 of the env regex applied to the compartment name
- Container type: `cdbroot` when the target name ends in `_CDBROOT`, else `pdb`
- `ContainerStage`: `{type}-{env}`, for example `cdbroot-prod` or `pdb-prod`

Set the regex once in `etc/datasafe.conf` as `DS_ENV_COMP_REGEX`, or pass
`--env-regex` per run.

## The change budget

`--limit N` caps the writes of a single run. Every write counts as one:

- one tag update
- one trail discovery
- one trail start

The budget is shared across all steps and is consumed in step order. With
`--limit 50` on a scope that needs 20 tag updates, a run performs the 20 tag
updates and then 30 discoveries or starts; everything beyond that is reported
as deferred and picked up by the next run.

`--limit 0` means unlimited. On a tenancy with more than a thousand targets that
is exactly the accident the waves exist to prevent - use it only on a scope you
have already narrowed with `--target-filter`.

## Rollout in waves

### 1. Look before you touch

```bash
bin/ds_audit_reconcile.sh --compartment-id ocid1.compartment.oc1..prod
```

Dry-run is the default. Nothing is written, the report shows what a run would
change.

### 2. Snapshot the state before the wave

```bash
bin/ds_trail_report.sh --compartment-id ocid1.compartment.oc1..prod \
    -f csv > wave-01-before.csv
```

### 3. Run the wave

```bash
bin/ds_audit_reconcile.sh --compartment-id ocid1.compartment.oc1..prod \
    --apply --limit 50 --report-file wave-01.txt
```

### 4. Check the volume before releasing the next wave

Collected volume only becomes visible after collection has been running for a
while, so leave time between the wave and the check.

```bash
bin/ds_trail_report.sh --compartment-id ocid1.compartment.oc1..prod --summary-only
```

```text
ENV       TARGETS COLLECTING  NOT_STARTED  NEEDS_ATTENTION  NO_TRAIL  OTHER     VOLUME
-------- -------- ---------- ------------ ---------------- --------- ------ ----------
prod          600         89          492                7        12      0     14.2GB
TOTAL         600         89          492                7        12      0     14.2GB
```

Volume per target in the wave should be plausible against the expected audit
rate. If it is not, stop and investigate before adding another 50 targets.

### 5. Repeat

The run is idempotent. Targets already collecting are skipped, so re-running
costs read calls and nothing else.

## Reporting for the SIEM handover

```bash
# Full machine readable state
bin/ds_trail_report.sh -A -f json > trail-state.json

# Only what still needs work
bin/ds_trail_report.sh -A --state NOT_STARTED,NO_TRAIL,NEEDS_ATTENTION

# Everything that a human has to look at
bin/ds_trail_report.sh -A --state NEEDS_ATTENTION -f csv
```

## Offline rehearsal

Both scripts can take a JSON snapshot instead of calling OCI. Useful to rehearse
a report, to reproduce a state later, or to hand a state to someone without
tenancy access.

```bash
bin/ds_trail_report.sh -A \
    --save-json t.json --save-trails-json tr.json --save-profiles-json pr.json

bin/ds_trail_report.sh \
    --input-json t.json --trails-json tr.json --profiles-json pr.json
```

`ds_audit_reconcile.sh` reads the same snapshots for a dry-run, but refuses
`--apply` from a target snapshot: a stale selection must never drive writes.

## Troubleshooting

| Symptom | Cause | Action |
| --- | --- | --- |
| `NO_TRAIL` and no audit profile | Data Safe never created an audit profile for the target | Check the target registration; the reconcile run reports it under manual attention |
| A target stays `NO_TRAIL` after `--apply` | Discovery is asynchronous | Re-run the reconcile; the trail appears when the work request completes |
| `NEEDS_ATTENTION` after a start | Usually a database side problem - credentials, missing privileges, or the audit trail location | Inspect with `bin/ds_target_audit_trail.sh --list -T <target>` and check `bin/ds_database_prereqs.sh` |
| Environment reported as `undef` | The target has no `DBSec.Environment` and no parsable `ContainerStage` | Run the tagging step, or check `DS_ENV_COMP_REGEX` against the compartment name |
| Volume stays at zero | Collection was just started, or the database produces no audit records | Wait, then re-check; verify unified auditing is enabled on the target |

## Non-goals

- No security policy distribution - Data Safe does that via target groups
- No deleting or stopping of trails
- No automatic handling of `NEEDS_ATTENTION` beyond reporting
- No backfill of historic audit data

## See also

- [Quick Reference](quickref.md)
- [Database Prereqs](database_prereqs.md)
- [IAM Policies Guide](oci-iam-policies.md)
