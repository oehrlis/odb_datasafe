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
