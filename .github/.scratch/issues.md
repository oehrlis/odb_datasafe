# Issues

## ds_target_update_service.sh

- does something when no parameter is specified but it should show help only
- current and new service is not shown correctly.

```bash
ds_target_update_service.sh -T exa101r04c08_cdb07b081_EPLSQ --dry-run
[2026-01-22 08:45:27] [INFO] Starting ds_target_update_service.sh v0.5.3
[2026-01-22 08:45:27] [INFO] Dry-run mode: Changes will be shown only (use --apply to apply)
[2026-01-22 08:45:27] [INFO] Processing specific targets...
[2026-01-22 08:45:37] [INFO] Target: exa101r04c08_cdb07b081_EPLSQ
[2026-01-22 08:45:37] [INFO]   Current service: 
[2026-01-22 08:45:37] [INFO]   New service: 
[2026-01-22 08:45:37] [INFO]   [OK] No change needed (already correct format)
[2026-01-22 08:45:37] [INFO] Service update completed:
[2026-01-22 08:45:37] [INFO]   Successful: 1
[2026-01-22 08:45:37] [INFO]   Errors: 0
[2026-01-22 08:45:37] [INFO] Service update completed successfully
```

## ds_target_delete.sh

- add wait flag default submit and do not wait (async)

## ds_target_move.sh

- does something when no parameter is specified but it should show help only
- add wait flag default submit and do not wait (async)
- fix current run issues

```bash
ds_target_move.sh -h
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_move.sh: line 433: init_script_env: command not found
[2026-01-22 08:50:40] [ERROR] 2
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Destination compartment (-D) is required: numeric argument required
[2026-01-22 08:50:44] [INFO] Destination compartment:  (Query returned empty result, no output to show.)
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_move.sh: line 176: ds_build_target_list: command not found
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_move.sh: line 179: ds_validate_and_fill_targets: command not found
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_move.sh: line 184: ds_resolve_targets_to_ocids: command not found
[2026-01-22 08:50:44] [ERROR] 1
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Failed to resolve targets to OCIDs.: numeric argument required
[2026-01-22 08:50:44] [INFO] Targets selected for move: 0
[2026-01-22 08:50:44] [ERROR] 1
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: No targets found to move.: numeric argument required
[2026-01-22 08:50:44] [WARN] This will MOVE 0 Data Safe target database(s)
[2026-01-22 08:50:44] [WARN] From: various compartments
[2026-01-22 08:50:45] [WARN] To: 
[2026-01-22 08:50:45] [WARN] Dependencies (audit trails, assessments, policies) will also be moved
Continue? [y/N]: n
[2026-01-22 08:50:49] [ERROR] 0
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Move cancelled by user.: numeric argument required
[2026-01-22 08:50:49] [INFO] Step 1/2: Moving target dependencies...
[2026-01-22 08:50:49] [INFO] Step 2/2: Moving target databases...
[2026-01-22 08:50:49] [INFO] Move summary:
[2026-01-22 08:50:49] [INFO]   Targets processed: 0
[2026-01-22 08:50:49] [INFO]   Successfully moved: 0
[2026-01-22 08:50:49] [INFO]   Failed moves: 0
[2026-01-22 08:50:49] [ERROR] 0
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Target move completed: numeric argument required
```

## ds_target_update_tags.sh

- does something when no parameter is specified but it should show help only
- does not work as expected

```bash
ds_target_update_tags.sh -T exa101r04c08_cdb07b081_EPLSQ --dry-run
[2026-01-22 08:53:10] [INFO] Starting ds_target_update_tags.sh v0.5.3
[2026-01-22 08:53:10] [INFO] Dry-run mode: Changes will be shown only (use --apply to apply)
[2026-01-22 08:53:10] [INFO] Processing specific targets...
[2026-01-22 08:53:10] [ERROR] Target name resolution not implemented yet: exa101r04c08_cdb07b081_EPLSQ
[2026-01-22 08:53:10] [INFO] Tag update completed:
[2026-01-22 08:53:10] [INFO]   Successful: 0
[2026-01-22 08:53:10] [INFO]   Errors: 1
[2026-01-22 08:53:10] [ERROR] Tag update failed with errors
```
