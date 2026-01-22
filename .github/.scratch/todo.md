# list todo

done    =>  ds_target_list.sh
done    =>  ds_target_list_connector.sh
done    =>  ds_target_refresh.sh
done    =>  ds_tg_report.sh
done    =>  ds_target_delete.sh
done    =>  template.sh
done    =>  ds_target_details.sh
done    =>  ds_find_untagged_targets.sh
done    =>  ds_target_update_credentials.sh
done    =>  install_datasafe_service.sh
done    =>  uninstall_all_datasafe_services.sh
done    =>  ds_target_update_service.sh
done    =>  ds_target_update_tags.sh
done    =>  ds_target_move.sh
done    =>  ds_target_update_connector.sh
done    =>  ds_target_connect_details.sh
done    =>  ds_target_export.sh
done    =>  ds_target_audit_trail.sh
done    =>  ds_target_register.sh

## Summary - All Scripts Refactored

All Data Safe scripts now use the new ds_lib.sh framework with:

- Deterministic caching for target lists (survives subshells)
- Normalized lifecycle filtering (comma-separated states)
- Consistent OCI wrapper usage (oci_exec, oci_exec_ro)
- Streamlined argument parsing and error handling
- Reduced redundant OCI calls via shared cache

## Remaining Items

exa101r04c04_cdb01b04_ISAMIPQ
delete does not work:
ds_target_delete.sh -T exa101r04c08_cdb07b081_EPLSQ --dry-run
[2026-01-22 08:22:46] [INFO] Starting ds_target_delete.sh v0.3.0
[2026-01-22 08:22:55] [INFO] Targets selected for deletion: 1
[2026-01-22 08:22:55] [INFO] Step 1/2: Deleting target dependencies...
[2026-01-22 08:22:55] [ERROR] Error in /Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_delete.sh at line 280 (exit code: 0)
[2026-01-22 08:22:55] [ERROR] Stack trace:
[2026-01-22 08:22:55] [ERROR]   at error_handler() in /Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh:177

ds_target_details.sh does not work at all:
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_details.sh: line 431: init_script_env: command not found
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_details.sh: line 178: ds_build_target_list: command not found
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_details.sh: line 181: ds_validate_and_fill_targets: command not found
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_target_details.sh: line 186: ds_resolve_targets_to_ocids: command not found
[2026-01-22 08:23:15] [ERROR] 1
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Failed to resolve targets to OCIDs.: numeric argument required
[2026-01-22 08:23:15] [INFO] Targets selected for details: 0
[2026-01-22 08:23:15] [WARN] No targets found matching criteria
[2026-01-22 08:23:15] [ERROR] 0
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: No targets to process: numeric argument required
[2026-01-22 08:23:15] [INFO] Collecting target details...
[2026-01-22 08:23:16] [INFO] Collected details for 0 targets (0 failed)
[2026-01-22 08:23:16] [INFO] Wrote 0 target details to ./datasafe_target_details.csv
[2026-01-22 08:23:16] [ERROR] 0
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/lib/common.sh: line 150: exit: Target details collection completed: numeric argument required

ds_find_untagged_targets.sh does not work:
[2026-01-22 08:23:53] [INFO] Starting ds_find_untagged_targets v0.5.3
[2026-01-22 08:23:56] [INFO] No compartment specified, using DS_ROOT_COMP: ocid1.compartment.oc1..aaaaaaaamvxhsrhtls7vdlmqh7zvtsbiic52iwauci4hvwbyzukpbb2oyoba
/Users/stefan.oehrli/Development/github/oehrlis/odb_datasafe/bin/ds_find_untagged_targets.sh: line 177: comp_name: unbound variable

ignore inactive by default
