Rem
Rem Copyright (c) 2023, Oracle and/or its affiliates.
Rem All rights reserved.
Rem
Rem    NAME
Rem      datasafe_privileges.sql
Rem
Rem    DESCRIPTION
Rem      This script contains grant/revoke privileges for audit collection/audit setting/data discovery
Rem      /data masking/assessment that are needed to setup a user.
Rem      This script should be run by SYS (or equivalent) user
Rem      This script takes in 5 parameters:
Rem         1. username (case sensitive matching the username from dba_users. For cases with single quote,
Rem            please enter with another quote. Ex: O''Brien)
Rem         2. type (grant/revoke)
Rem         3. mode (audit_collection/audit_setting/data_discovery/masking/assessment/sql_firewall/all)
Rem         4. -RDSORACLE - This must be passed for RDS For Oracle Database
Rem         5. -VERBOSE will only show the actual grant/revoke commands. This is optional
Rem      To run the script
Rem         @datasafe_privileges.sql <username> <GRANT/REVOKE> <AUDIT_COLLECTION/AUDIT_SETTING/DATA_DISCOVERY/MASKING/ASSESSMENT/SQL_FIREWALL/ALL> [-RDSORACLE] [-VERBOSE]
Rem
Rem    WARNING
Rem      If you are running the revoke functionality of this script on existing user, it could revoke
Rem      existing privileges granted to the user. You will have to manually grant them back to the
Rem      user.
Rem      If you are revoking privileges for a specific feature, overlapping privileges would be
Rem      revoked, you will need to grant the privileges back for the features you still want to use.
Rem
Rem    NOTE
Rem      If the target database has the Database Vault option enabled, it blocks some privileges and roles
Rem      that are to be granted when this script is run. Depending on how Database Vault is configured,
Rem      Data Safe may also be blocked from running some features, or features like Data Discovery and
Rem      Data Masking may not run on Database Vault protected data. To allow Data Safe to have the required
Rem      privileges/roles and be fully functional, please contact the person in charge of database security
Rem      or Database Vault for this database (user with DV_OWNER or DV_ADMIN role).


WHENEVER SQLERROR EXIT;

SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON FORMAT WRAPPED

set termout on
prompt Enter value for USERNAME (case sensitive matching the username from dba_users)
set termout off
define user = '&1'
set termout on
prompt Setting USERNAME to &user

prompt Enter value for TYPE (grant/revoke)
set termout off
define type = &2
set termout on
prompt Setting TYPE to &type

prompt Enter value for MODE (audit_collection/audit_setting/data_discovery/masking/assessment/sql_firewall/all)
set termout off
define mode = &3
set termout on
prompt Setting MODE to &mode

column 4 new_value 4 noprint
select '' "4" from dual where rownum = 0;
define dbtype = &4 "-default"

-- The last parameter is optional
column 5 new_value 5 noprint
select '' "5" from dual where rownum = 0;
define verbose = &5 "default"


DECLARE
  db_type varchar2(30);
  pkg_count  number := 0;
  role_count number := 0;
  ex_custom EXCEPTION;
  PRAGMA EXCEPTION_INIT(ex_custom, -20000);
BEGIN
  db_type:= upper(substr('&dbtype', 1, 20));
  IF (db_type is null)
  THEN
    db_type := '-ORACLE';
  END IF;
  SELECT count(*) INTO pkg_count
      FROM sys.all_objects
      WHERE owner = 'RDSADMIN' AND object_name = 'RDSADMIN_UTIL';

  SELECT count(*) INTO role_count
      FROM sys.dba_role_privs
      WHERE granted_role = 'RDS_MASTER_ROLE';

  IF (db_type = '-RDSORACLE' OR INSTR(db_type, '-RDSORACLE', 1) > 0)
  THEN
    IF (pkg_count > 0 and role_count > 0)
    THEN
	  EXECUTE IMMEDIATE ( 'ALTER SESSION SET PLSQL_CCFLAGS='
	                                      || '''RDSADMIN_UTIL_EXIST:true''' );
    ELSE
      raise_application_error( -20000, 'It is not an RDS For Oracle Database. Please run the script without -RDSORACLE option' );
    END IF;
  ELSIF (db_type = '-ORACLE' OR INSTR(db_type, '-ORACLE', 1) > 0 OR INSTR(db_type, '-VERBOSE', 1) > 0)
  THEN
    IF (pkg_count > 0 and role_count > 0)
    THEN
      raise_application_error( -20000, 'It is an RDS For Oracle Database. Please run the script with -RDSORACLE option' );
    END IF;
  ELSE
    EXECUTE IMMEDIATE ( 'ALTER SESSION SET PLSQL_CCFLAGS='
                                    || '''RDSADMIN_UTIL_EXIST:false''' );
  END IF;
END;
/

DECLARE
  ver        VARCHAR2(30);
  username   VARCHAR2(128);
  v_user     VARCHAR2(128);
  v_count_user NUMBER;
  v_type     VARCHAR2(6);
  v_mode     VARCHAR2(20);
  v_code     NUMBER;
  v_errm     VARCHAR2(64);
  v_verbose  VARCHAR2(30);
  priv_type  VARCHAR2(10);
  pkgcount   PLS_INTEGER;
  v_stmt     VARCHAR2(256);
  v_isPureUnified   VARCHAR2(10);
  usage_string   CONSTANT VARCHAR(256) := '@datasafe_privileges.sql <username> <GRANT/REVOKE> <AUDIT_COLLECTION/AUDIT_SETTING/DATA_DISCOVERY/MASKING/ASSESSMENT/SQL_FIREWALL/ALL> [-RDSORACLE] [-VERBOSE]';
  role_prefix VARCHAR2(60) := 'ORA_DSCS_';
  role_name VARCHAR2(128);
  role_exist NUMBER;
  v_role     VARCHAR2(64);
  v_tableSpace VARCHAR2(30);
  v_targetType VARCHAR2(30);
  v_warning VARCHAR(200) := null;
  v_warning_audit VARCHAR(200) := null;
  v_assessWarning VARCHAR(2000) := null;
  v_isValid BOOLEAN;
  v_flashback VARCHAR2(30);
  v_dbtype   VARCHAR2(30);
  v_con_id NUMBER;
  v_common_user_prefix VARCHAR2(50);
  v_is_rdsfororacle BOOLEAN := FALSE;
  dv VARCHAR2(10);
  v_dv_issue VARCHAR2(10):= 'FALSE';
  v_dv_errmsg VARCHAR(500) := null;
  v_sql VARCHAR2(4000);

  PROCEDURE execute_stmt(sql_stmt VARCHAR2) IS
  BEGIN
    IF (v_verbose = '-VERBOSE')
    THEN
      v_sql := 'BEGIN ' ||
        'sys.dbms_output.put_line('' ' || sql_stmt ||' ''); ' ||
        'END;';
      execute immediate v_sql;
    END IF;
    EXECUTE IMMEDIATE sql_stmt;
  EXCEPTION
    WHEN OTHERS THEN
    IF (SQLCODE = -1927 OR SQLCODE = -1951 OR SQLCODE = -1952)
    THEN
      RETURN;
    ELSE
      RAISE;
    END IF;
  END;

  PROCEDURE execute_object_grant(object_owner VARCHAR2, object_name VARCHAR2,
			 grantee VARCHAR2, priv_type VARCHAR2) AS
     sql_stmt VARCHAR2(500);
     grantee_name VARCHAR2(500);
  BEGIN

$IF $$RDSADMIN_UTIL_EXIST $THEN
    grantee_name := (TRIM(BOTH '"' FROM grantee));
    IF (v_is_rdsfororacle)
    THEN
      BEGIN
        rdsadmin.rdsadmin_util.grant_sys_object(
                  p_obj_name  => object_name,
                  p_grantee   => grantee_name,
                  p_privilege => priv_type);
      EXCEPTION
        WHEN OTHERS THEN
          IF (SQLCODE = -20199 and priv_type = 'READ')
          THEN
            rdsadmin.rdsadmin_util.grant_sys_object(
                  p_obj_name  => object_name,
                  p_grantee   => grantee_name,
                  p_privilege => 'SELECT');
           ELSE
             RAISE;
           END IF;
      END;
    END IF;
$ELSE
    sql_stmt := 'GRANT '|| priv_type ||' ON '|| object_owner||'.'||object_name||
      	        ' TO '|| grantee;
	execute_stmt(sql_stmt);
$END
  EXCEPTION
    WHEN OTHERS THEN
    IF (SQLCODE = -1927 OR SQLCODE = -1951 OR SQLCODE = -1952 OR SQLCODE = -20199)
    THEN
      RETURN;
    ELSE
      RAISE;
    END IF;
  END;

  PROCEDURE print_revoke_message(role_name VARCHAR2, username VARCHAR2) IS
  BEGIN
    v_sql := 'BEGIN ' ||
       'sys.dbms_output.new_line(); ' ||
       'sys.dbms_output.put_line(''Revoking ' || role_name || ' privileges from ' || username || ' ... ''); ' ||
       'END;';
    execute immediate v_sql;
  END;

  PROCEDURE execute_enquote_role_name(role_prefix VARCHAR2, role_name VARCHAR2) IS
  v_role_name varchar2(128);
  BEGIN
    v_role_name := role_prefix || role_name;
    /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
    revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
    v_sql := 'begin ' ||
      ':v_role := sys.dbms_assert.enquote_name(:v_role_name, FALSE);' ||
      ' end;';
    execute immediate v_sql using out v_role, in v_role_name;
  END;

  PROCEDURE revoke_object_grant(object_owner VARCHAR2, object_name VARCHAR2,
			 grantee VARCHAR2, priv_type VARCHAR2) AS
     sql_stmt VARCHAR2(500);
	 grantee_name VARCHAR2(500);
  BEGIN

$IF $$RDSADMIN_UTIL_EXIST $THEN
    grantee_name := (TRIM(BOTH '"' FROM grantee));
    IF (v_is_rdsfororacle)
    THEN
      BEGIN
        rdsadmin.rdsadmin_util.revoke_sys_object(
                  p_obj_name  => object_name,
                  p_revokee   => grantee_name,
                  p_privilege => priv_type);
      EXCEPTION
        WHEN OTHERS THEN
          IF (SQLCODE = -20199 and priv_type = 'READ')
          THEN
            rdsadmin.rdsadmin_util.revoke_sys_object(
                  p_obj_name  => object_name,
                  p_revokee   => grantee_name,
                  p_privilege => 'SELECT');
          ELSE
            RAISE;
          END IF;
      END;
    END IF;
$ELSE
    sql_stmt := 'REVOKE '|| priv_type ||' ON '|| object_owner||'.'||object_name||
      	        ' FROM '|| grantee;
	execute_stmt(sql_stmt);
$END
  EXCEPTION
    WHEN OTHERS THEN
    /* 1927 - cannot REVOKE privileges you did not grant
       1951 - Role "role_name" not granted to user
       1952 - system privileges not granted to user
       20199 - custom errors created by developers using RAISE_APPLICATION_ERROR */
    IF (SQLCODE = -1927 OR SQLCODE = -1951 OR SQLCODE = -1952 OR SQLCODE = -20199)
    THEN
      RETURN;
    ELSE
      RAISE;
    END IF;
  END;

  PROCEDURE execute_stmt_ignore_failed(sql_stmt VARCHAR2) IS
  BEGIN
    IF (v_verbose = '-VERBOSE')
    THEN
      sys.dbms_output.put_line(sql_stmt);
    END IF;
    EXECUTE IMMEDIATE sql_stmt;
  EXCEPTION
    WHEN OTHERS THEN
      sys.DBMS_OUTPUT.PUT_LINE(sql_stmt);
  END;

  PROCEDURE grant_audit_viewer(role_name VARCHAR2, priv_type VARCHAR2) IS
  BEGIN
    IF (v_is_rdsfororacle)
    THEN
      execute_object_grant('SYS','GV_$ASM_AUDIT_CLEAN_EVENTS',role_name,priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CLEAN_EVENTS',role_name,priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_CLEANUP_JOBS',role_name,priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CLEANUP_JOBS',role_name,priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_CONFIG_PARAMS',role_name,priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CONFIG_PARAMS',role_name,priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_LAST_ARCH_TS',role_name,priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_LAST_ARCH_TS',role_name,priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_LOAD_JOBS',role_name,priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_LOAD_JOBS',role_name,priv_type);
      execute_object_grant('SYS','V_$UNIFIED_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','GV_$UNIFIED_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','V_$UNIFIED_AUDIT_RECORD_FORMAT',role_name,priv_type);
      execute_object_grant('SYS','DBA_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','DBA_TABLES', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_POLICIES',role_name,priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_ENABLED_POLICIES',role_name,priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_CONTEXTS',role_name,priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_POLICY_COMMENTS',role_name,priv_type);
      execute_object_grant('SYS','DBA_FGA_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','CDB_FGA_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','DBA_COMMON_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','CDB_COMMON_AUDIT_TRAIL',role_name,priv_type);
      execute_object_grant('SYS','DBA_XS_AUDIT_POLICY_OPTIONS',role_name,priv_type);
      execute_object_grant('SYS','CDB_XS_AUDIT_POLICY_OPTIONS',role_name,priv_type);
      execute_object_grant('SYS','DBA_XS_ENABLED_AUDIT_POLICIES',role_name,priv_type);
      execute_object_grant('SYS','CDB_XS_ENABLED_AUDIT_POLICIES',role_name,priv_type);
      execute_object_grant('SYS','DBMS_AUDIT_UTIL', role_name, 'EXECUTE');

      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.UNIFIED_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.CDB_UNIFIED_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DBA_XS_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.CDB_XS_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DV$CONFIGURATION_AUDIT to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DV$ENFORCEMENT_AUDIT to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON LBACSYS.OLS$AUDIT_ACTIONS to '|| role_name);
      execute_stmt_ignore_failed('GRANT EXECUTE on LBACSYS.ORA_GET_AUDITED_LABEL to '|| role_name);
    ELSE
      execute_stmt('GRANT AUDIT_VIEWER TO '||role_name);
    END IF;

  EXCEPTION
  WHEN OTHERS THEN
    IF (SQLCODE = -1927 OR SQLCODE = -1951 OR SQLCODE = -1952 OR SQLCODE = -20199)
    THEN
      RETURN;
    ELSE
      RAISE;
    END IF;
  END;

  PROCEDURE grant_audit_admin(role_name VARCHAR2, priv_type VARCHAR2) IS
  BEGIN
    IF (v_is_rdsfororacle)
    THEN
      execute_stmt('GRANT AUDIT ANY  to '|| role_name);
      execute_stmt('GRANT AUDIT SYSTEM  to '|| role_name);

      execute_object_grant('SYS','GV_$ASM_AUDIT_CLEAN_EVENTS', role_name, priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CLEAN_EVENTS', role_name, priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_CLEANUP_JOBS', role_name, priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CLEANUP_JOBS', role_name, priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_CONFIG_PARAMS', role_name, priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_CONFIG_PARAMS', role_name, priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_LAST_ARCH_TS', role_name, priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_LAST_ARCH_TS', role_name, priv_type);
      execute_object_grant('SYS','GV_$ASM_AUDIT_LOAD_JOBS', role_name, priv_type);
      execute_object_grant('SYS','V_$ASM_AUDIT_LOAD_JOBS', role_name, priv_type);
      execute_object_grant('SYS','V_$UNIFIED_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','GV_$UNIFIED_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','V_$UNIFIED_AUDIT_RECORD_FORMAT', role_name, priv_type);
      execute_object_grant('SYS','DBA_OBJECTS', role_name, priv_type);
      execute_object_grant('SYS','DBA_OBJECTS_AE', role_name, priv_type);
      execute_object_grant('SYS','DBA_USERS', role_name, priv_type);
      execute_object_grant('SYS','DBA_TABLES', role_name, priv_type);
      execute_object_grant('SYS','DBA_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_POLICIES', role_name, priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_ENABLED_POLICIES', role_name, priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_CONTEXTS', role_name, priv_type);
      execute_object_grant('SYS','AUDIT_UNIFIED_POLICY_COMMENTS', role_name, priv_type);
      execute_object_grant('SYS','DBA_ROLES', role_name, priv_type);
      execute_object_grant('SYS','CDB_ROLES', role_name, priv_type);
      execute_object_grant('SYS','DBA_AUDIT_MGMT_CONFIG_PARAMS', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_MGMT_CONFIG_PARAMS', role_name, priv_type);
      execute_object_grant('SYS','DBA_AUDIT_MGMT_LAST_ARCH_TS', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_MGMT_LAST_ARCH_TS', role_name, priv_type);
      execute_object_grant('SYS','DBA_AUDIT_MGMT_CLEANUP_JOBS', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_MGMT_CLEANUP_JOBS', role_name, priv_type);
      execute_object_grant('SYS','DBA_AUDIT_MGMT_CLEAN_EVENTS', role_name, priv_type);
      execute_object_grant('SYS','DBA_FGA_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','CDB_AUDIT_MGMT_CLEAN_EVENTS', role_name, priv_type);
      execute_object_grant('SYS','CDB_FGA_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','DBA_COMMON_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','CDB_COMMON_AUDIT_TRAIL', role_name, priv_type);
      execute_object_grant('SYS','DBA_XS_AUDIT_POLICY_OPTIONS', role_name, priv_type);
      execute_object_grant('SYS','CDB_XS_AUDIT_POLICY_OPTIONS', role_name, priv_type);
      execute_object_grant('SYS','DBA_XS_ENABLED_AUDIT_POLICIES', role_name, priv_type);
      execute_object_grant('SYS','CDB_XS_ENABLED_AUDIT_POLICIES', role_name, priv_type);
      execute_object_grant('SYS','DBMS_FGA', role_name, 'EXECUTE');
      execute_object_grant('SYS','DBMS_AUDIT_UTIL', role_name, 'EXECUTE');

      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.UNIFIED_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.CDB_UNIFIED_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DBA_XS_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.CDB_XS_AUDIT_TRAIL to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DV$CONFIGURATION_AUDIT to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON AUDSYS.DV$ENFORCEMENT_AUDIT to '|| role_name);
      execute_stmt_ignore_failed('GRANT ' || priv_type || ' ON LBACSYS.OLS$AUDIT_ACTIONS to '|| role_name);
      execute_stmt_ignore_failed('GRANT EXECUTE on AUDSYS.DBMS_AUDIT_MGMT to '|| role_name);
      execute_stmt_ignore_failed('GRANT EXECUTE on LBACSYS.ORA_GET_AUDITED_LABEL to '|| role_name);
    ELSE
      execute_stmt('GRANT AUDIT_ADMIN TO '|| v_role);
    END IF;
  EXCEPTION
  WHEN OTHERS THEN
    IF (SQLCODE = -1927 OR SQLCODE = -1951 OR SQLCODE = -1952 OR SQLCODE = -20199)
    THEN
      RETURN;
    ELSE
      RAISE;
    END IF;
  END;

  PROCEDURE create_role(feature_name VARCHAR2) IS
  v_role_name varchar2(128);
  BEGIN
  v_role_name := role_prefix || feature_name;
  /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
  revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
    v_sql := 'begin ' ||
          ':role_name := sys.dbms_assert.enquote_name(:v_role_name, FALSE);' ||
          ' END;';
    execute immediate v_sql using out role_name, in v_role_name;
    execute immediate 'select count(*) from SYS.DBA_ROLES where role = :1'
            into role_exist using role_name;
    IF (role_exist = 0)
    THEN
      execute_stmt('CREATE ROLE ' || role_name);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_code := SQLCODE;
    IF (v_code = -1921)
    THEN
  	  null;
  	ELSE RAISE;
  	END IF;
  END;

  -- Procedure to check if pure unified auditing
  PROCEDURE check_if_pure_unified(v_isPureUnified OUT VARCHAR2) AS
  BEGIN
    EXECUTE IMMEDIATE 'select upper(value) from v$option where parameter = :1'
            into v_isPureUnified using 'Unified Auditing';
    IF (v_isPureUnified is null)
    THEN
       v_isPureUnified := 'FALSE';
    END IF;
  EXCEPTION
  WHEN OTHERS THEN
    v_isPureUnified := 'FALSE';
  END;

  PROCEDURE check_if_dv_enabled(dv OUT VARCHAR2) IS
              dv_count NUMBER;
    BEGIN
      EXECUTE IMMEDIATE 'SELECT upper(value) FROM v$option where parameter = ''Oracle Database Vault'''
              into dv ;
      IF (dv = 'TRUE' and ver < '12.1%')
      THEN
         Execute IMMEDIATE 'SELECT count(role) FROM SYS.DBA_ROLES where role in(''DV_MONITOR'',''DV_SECANALYST'')'
                 into dv_count;
         IF (dv_count != 2)
         THEN
            dv := 'FALSE';
         END IF;
      END IF;
  END;

  PROCEDURE dv_authorize_audit(v_mode VARCHAR2) IS
      BEGIN
          IF (v_mode = 'AUDIT_COLLECTION')
          THEN
                sys.dbms_output.put_line('BEGIN');
                sys.dbms_output.put_line('DBMS_MACADM.AUTHORIZE_AUDIT_VIEWER('''||v_user||''');');
                sys.dbms_output.put_line('EXCEPTION WHEN OTHERS THEN IF(SQLCODE = -47899) THEN NULL; ELSE RAISE; END IF; END;');
                sys.dbms_output.put_line('/');
          ELSE
                sys.dbms_output.put_line('EXEC  DBMS_MACADM.AUTHORIZE_AUDIT_ADMIN('''||v_user||''');');
          END IF;

          IF (v_dv_issue='TRUE')
          THEN
              sys.dbms_output.put_line('EXEC  DBMS_MACADM.AUTHORIZE_AUDIT_ADMIN(''SYS'');');
              sys.dbms_output.put_line('Please re-run the script after granting the above privileges.');
              sys.dbms_output.put_line('The following exception occured during the script execution.');
              sys.dbms_output.put_line(v_dv_errmsg);
          ELSE
            IF (v_mode = 'AUDIT_COLLECTION' or v_mode = 'ALL')
            THEN
                sys.dbms_output.put_line('EXEC  DBMS_MACADM.UNAUTHORIZE_AUDIT_ADMIN(''SYS'');');
            END IF;
          END IF;
  END;

 PROCEDURE dv_authorize_assessment(v_mode VARCHAR2) IS
      BEGIN
          IF (v_mode = 'ASSESSMENT')
          THEN
              sys.dbms_output.put_line('EXEC  DBMS_MACADM.AUTHORIZE_AUDIT_ADMIN('''||v_user||''');');
          END IF;

          IF (v_dv_issue='TRUE')
          THEN
              sys.dbms_output.put_line('EXEC  DBMS_MACADM.AUTHORIZE_AUDIT_ADMIN(''SYS'');');
              sys.dbms_output.put_line('Please re-run the script after granting the above privileges.');
              sys.dbms_output.put_line('The following exception occured during the script execution.');
              sys.dbms_output.put_line(v_dv_errmsg);
          END IF;
    END;

  -- Procedure to check if DV is enabled and running corresponding privilege
  PROCEDURE execute_dv(type VARCHAR2, username VARCHAR2, v_mode VARCHAR2, v_warning VARCHAR2) IS
            dv_count NUMBER;
  BEGIN

    IF (dv = 'TRUE')
    THEN
      sys.dbms_output.put_line('*NOTE*');
      sys.dbms_output.put_line('======');
      sys.dbms_output.new_line();
      sys.dbms_output.put_line('The target has the Database Vault option enabled.');
      sys.dbms_output.put_line('Database Vault blocks some privileges and roles that are to be granted when this script is run.');
      sys.dbms_output.put_line('Depending on how Database Vault is configured, Data Safe may also be blocked from running ');
      sys.dbms_output.put_line('some features, or features like Data Discovery and Data Masking may not run on Database Vault protected data.');
      sys.dbms_output.put_line('To allow Data Safe to have the required privileges/roles and be fully functional, please contact ');
      sys.dbms_output.put_line('the person in charge of database security or Database Vault for this database (user with DV_OWNER or DV_ADMIN role).');
      sys.dbms_output.new_line();

       IF (v_mode != 'DATA_DISCOVERY' AND v_mode != 'MASKING')
       THEN
          sys.dbms_output.put_line('Connect to the secured target database with a user with DV_OWNER role and execute:');
          sys.dbms_output.new_line();
       END IF;

       IF (type = 'GRANT')
       THEN
          IF (v_mode = 'ASSESSMENT' or v_mode = 'ALL')
          THEN
            sys.dbms_output.put_line('GRANT DV_SECANALYST to '||username||';');
            IF (v_warning is not null)
            THEN
              sys.dbms_output.put_line(v_warning);
            END IF;
            IF (ver >= '23.0.0%')
            THEN
                dv_authorize_assessment(v_mode);
            END IF;
          END IF;
          IF (v_mode = 'AUDIT_COLLECTION' or v_mode = 'AUDIT_SETTING' or v_mode = 'ALL')
          THEN
            IF (v_mode = 'AUDIT_COLLECTION' or v_mode = 'ALL')
            THEN
                sys.dbms_output.put_line('GRANT DV_MONITOR to '||username||';');
            END IF;
            IF (ver >= '23.0.0%')
            THEN
                dv_authorize_audit(v_mode);
            END IF;
          END IF;
          IF (v_mode = 'DATA_DISCOVERY' or v_mode = 'MASKING' or v_mode = 'ALL')
          THEN
            sys.dbms_output.put_line('For Data Discovery or Data Masking feature refer the above note to grant required authorization.');
          END IF;
          IF ((v_mode = 'SQL_FIREWALL' or v_mode = 'ALL') AND (ver >= '23.0.0%'))
          THEN
              sys.dbms_output.put_line('Update the second argument in DBMS_MACADM.AUTHORIZE_SQL_FIREWALL to either Y or N before executing the PLSQL:');
              sys.dbms_output.put_line('- Y : Data safe can create SQL collection and SQL firewall policies on users with DV_OWNER/DV_ACCTMGR role');
              sys.dbms_output.put_line('- N : Data safe cannot create SQL collection and SQL firewall policies on users with DV_OWNER/DV_ACCTMGR role (default value)');
              sys.dbms_output.new_line();
              sys.dbms_output.put_line('EXEC DBMS_MACADM.AUTHORIZE_SQL_FIREWALL('''||username||''',''Y''/''N'');');
              sys.dbms_output.put_line('EXEC  DBMS_MACADM.AUTHORIZE_AUDIT_ADMIN('''||username||''');');
          END IF;
       END IF;

       IF (type = 'REVOKE')
       THEN
          IF (v_mode = 'AUDIT_COLLECTION' or v_mode = 'ALL')
          THEN
             sys.dbms_output.put_line('REVOKE DV_MONITOR from '||username||';');
             IF (ver >= '23.0.0%' and v_mode = 'AUDIT_COLLECTION')
              THEN
                 sys.dbms_output.put_line('EXEC  DBMS_MACADM.UNAUTHORIZE_AUDIT_VIEWER('''||v_user||''');');
              END IF;
          END IF;
          IF (ver >= '23.0.0%' and (v_mode = 'AUDIT_SETTING' or v_mode = 'ALL'))
          THEN
             sys.dbms_output.put_line('EXEC  DBMS_MACADM.UNAUTHORIZE_AUDIT_ADMIN('||v_user||');');
          END IF;
          IF (v_mode = 'ASSESSMENT' or v_mode = 'ALL')
          THEN
              sys.dbms_output.put_line('REVOKE DV_SECANALYST from '''||v_user||''';');
          END IF;
          IF (v_mode = 'DATA_DISCOVERY' or v_mode = 'MASKING' or v_mode = 'ALL')
          THEN
             sys.dbms_output.put_line('For Data Discovery or Data Masking feature refer the above note to revoke the granted authorization.');
          END IF;
          IF ((v_mode = 'SQL_FIREWALL' or v_mode = 'ALL') AND (ver >= '23.0.0%'))
           THEN
               sys.dbms_output.put_line('EXEC DBMS_MACADM.UNAUTHORIZE_SQL_FIREWALL('''||username||''',''Y''/''N'');');
               sys.dbms_output.put_line('EXEC  DBMS_MACADM.UNAUTHORIZE_AUDIT_ADMIN('''||username||''');');
           END IF;
       END IF;
       sys.dbms_output.new_line();
    END IF;

    EXCEPTION
      WHEN OTHERS THEN
        IF (SQLCODE != -1403 AND SQLCODE != 100) -- No data found
        THEN
          RAISE;
        END IF;
  END; --End procedure execute_dv

  -- Procedure to check if input parameters are valid
  FUNCTION validate_input_parameters
  return BOOLEAN AS
  BEGIN
    BEGIN
       v_user := '&user';
       v_type := upper('&type');
       v_mode := upper('&mode');
       v_verbose := upper('&verbose');
       v_dbtype := upper('&dbtype');

    EXCEPTION
      WHEN VALUE_ERROR THEN
      -- This might occur when the user specifies arguments longer than anticipated
         sys.dbms_output.put_line('ERROR: Please run the script with these parameters: ');
         sys.dbms_output.put_line(usage_string);
         sys.dbms_output.put_line('');
         sys.dbms_output.put_line('');
         return FALSE;
    END;

    IF (v_dbtype is null or v_dbtype = '-DEFAULT' or
        INSTR(v_dbtype, '-ORACLE', 1) > 0)
    THEN
        v_dbtype := '-ORACLE';
    ELSIF (INSTR(v_dbtype, '-VERBOSE', 1) > 0)
    THEN
	    v_dbtype := '-ORACLE';
	    v_verbose := '-VERBOSE';
    ELSIF (INSTR(v_dbtype, '-RDSORACLE', 1) > 0)
    THEN
        v_dbtype := '-RDSORACLE';
        v_is_rdsfororacle := TRUE;
    END IF;
    IF (INSTR(v_verbose, '-VERBOSE', 1) > 0)
    THEN
      v_verbose := '-VERBOSE';
    END IF;

    IF (v_user is null)
    THEN
       sys.dbms_output.put_line('ERROR: Argument #1 Username must not be null');
       sys.dbms_output.put_line('Please run the script with these parameters: ');
       sys.dbms_output.put_line(usage_string);
       sys.dbms_output.put_line('');
       sys.dbms_output.put_line('');
       return FALSE;
    END IF;
    /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
    revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
    v_sql := 'begin ' ||
          ':username:= sys.dbms_assert.schema_name(:v_user); ' ||
          'end;';
    execute immediate v_sql using out username, in v_user;

    EXECUTE IMMEDIATE 'SELECT COUNT(*) from all_users where username=:1'
                       into v_count_user using username;
    IF( v_count_user = 0)
    THEN
       sys.dbms_output.put_line('ERROR: Argument #1 User '|| username || ' does not exist.');
       sys.dbms_output.put_line('Please input an existing user as the parameter.');
       return FALSE;
    END IF;

   IF (v_type!='GRANT' and v_type!='REVOKE' or v_type is null)
   THEN
      sys.dbms_output.put_line('ERROR: Invalid argument #2 Type: ' || v_type);
      sys.dbms_output.put_line('Please run the script with these parameters: ');
      sys.dbms_output.put_line(usage_string);
      sys.dbms_output.put_line('');
      sys.dbms_output.put_line('');
      return FALSE;
   END IF;

   IF (v_mode !='AUDIT_COLLECTION' and v_mode !='AUDIT_SETTING'
      AND v_mode != 'DATA_DISCOVERY' AND v_mode != 'MASKING'
      AND v_mode != 'ASSESSMENT' AND v_mode != 'SQL_FIREWALL'
      AND v_mode != 'ALL' or v_mode is null)
   THEN
      sys.dbms_output.put_line('ERROR: Invalid argument #3 Mode:' || v_mode);
      sys.dbms_output.put_line('Please run the script with these parameters: ');
      sys.dbms_output.put_line(usage_string);
      sys.dbms_output.put_line('');
      sys.dbms_output.put_line('');
      return FALSE;
   END IF;


   IF (v_dbtype != '-ORACLE' and v_dbtype != '-RDSORACLE')
   THEN
      sys.dbms_output.put_line('ERROR: Invalid argument #4 dbtype:' || v_dbtype);
      sys.dbms_output.put_line('Please run the script with these parameters: ');
      sys.dbms_output.put_line(usage_string);
      sys.dbms_output.put_line('');
      sys.dbms_output.put_line('');
      return FALSE;
   END IF;

   IF (v_dbtype is not null and v_dbtype = '-RDSORACLE') THEN
	  v_dbtype := '-RDSORACLE';
	  v_is_rdsfororacle := TRUE;
   ELSE
	v_dbtype := '-ORACLE';
   END IF;

   return TRUE;
  END; -- End function validate_input_parameters

  FUNCTION check_view_exists(l_owner VARCHAR2, l_view VARCHAR2)
    RETURN boolean AS
    cnt NUMBER := 0;
  BEGIN
    IF (v_verbose = '-VERBOSE') THEN
      sys.dbms_output.put_line('Checking view ' || l_owner || '.' || l_view || ' existence');
    END IF;

    SELECT count(*) INTO cnt FROM SYS.DBA_VIEWS WHERE OWNER = l_owner
    and VIEW_NAME = l_view;
    IF cnt = 0 THEN
      IF (v_verbose = '-VERBOSE') THEN
        sys.dbms_output.put_line('View ' || l_owner || '.' || l_view || ' does not exist');
      END IF;

      RETURN FALSE;
    ELSE
      IF (v_verbose = '-VERBOSE') THEN
        sys.dbms_output.put_line('View ' || l_owner || '.' || l_view || ' exists');
      END IF;

      RETURN TRUE;
    END IF;
  END; -- End function check_view_exists

  FUNCTION check_user_exists(l_user VARCHAR2)
    RETURN boolean AS
    cnt NUMBER := 0;
  BEGIN
    SELECT count(*) INTO cnt FROM SYS.DBA_USERS WHERE USERNAME = l_user;
    IF cnt = 0 THEN
      IF (v_verbose = '-VERBOSE') THEN
        sys.dbms_output.put_line('User ' || l_user || ' does not exist');
      END IF;
      RETURN FALSE;
    ELSE
      IF (v_verbose = '-VERBOSE') THEN
        sys.dbms_output.put_line('User ' || l_user || ' exists');
      END IF;
      RETURN TRUE;
    END IF;
  END; -- End function check_user_exists

  PROCEDURE execute_audit_collection_mode(username VARCHAR2) AS
  BEGIN
    IF(ver < '11.2.0.4%')
  	THEN
       sys.dbms_output.put_line('ERROR: Oracle DB Version '||ver||' is not supported');
       sys.dbms_output.put_line('');
       sys.dbms_output.put_line('');
       return;
  	END IF;

  	IF (ver >= '12.1.0.2%')
  	THEN
       priv_type := 'READ';
  	ELSE
       priv_type := 'SELECT';
  	END IF;

    execute_enquote_role_name(role_prefix, 'AUDIT_COLLECTION');

    IF (v_type = 'GRANT')
    THEN
       BEGIN
           sys.dbms_output.new_line();
           sys.dbms_output.put_line('Granting AUDIT_COLLECTION privileges to '|| username ||' ... ');
           create_role('AUDIT_COLLECTION');
           execute_stmt('GRANT CREATE SESSION to ' || v_role);

      IF (ver >= '12.1%')
      THEN
        grant_audit_viewer(v_role, 'SELECT');
      END IF;

      IF (v_isPureUnified = 'FALSE')
      THEN
        execute_object_grant('SYS', 'AUD$', v_role, 'SELECT');
        execute_object_grant('SYS', 'FGA_LOG$', v_role, 'SELECT');
      END IF;

	  execute_object_grant('SYS', 'DBA_AUDIT_MGMT_CLEANUP_JOBS', v_role, priv_type);
	  execute_object_grant('SYS', 'V_$PWFILE_USERS', v_role, priv_type);
	  execute_object_grant('SYS','DBA_TABLES', v_role, priv_type);

	  execute_object_grant('SYS','DUAL', v_role, 'SELECT');
	  execute_object_grant('SYS','V_$OPTION', v_role, priv_type);
	  execute_object_grant('SYS','DEFAULT_JOB_CLASS', v_role, 'EXECUTE');
	  execute_object_grant('SYS','DBMS_OUTPUT', v_role, 'EXECUTE');
      execute_object_grant('SYS','STMT_AUDIT_OPTION_MAP', v_role, priv_type);
      execute_object_grant('SYS','XMLTYPE', v_role, 'EXECUTE');
      execute_object_grant('SYS','SYSTEM_PRIVILEGE_MAP', v_role, priv_type);
      execute_object_grant('SYS','DATABASE_PROPERTIES', v_role, priv_type);
      execute_object_grant('SYS','SESSION_ROLES', v_role, priv_type);
      execute_object_grant('SYS','SESSION_PRIVS', v_role, priv_type);
      execute_object_grant('SYS','ALL_TAB_PRIVS', v_role, priv_type);
      execute_object_grant('SYS','PRODUCT_COMPONENT_VERSION', v_role, priv_type);

      execute_stmt('GRANT ' || priv_type || ' ON SYS.ALL_USERS to '|| v_role);
      execute_stmt('GRANT ' || priv_type || ' ON SYS.DBA_ROLES to '|| v_role);
      execute_stmt('GRANT ' || priv_type || ' ON SYS.DBA_SYS_PRIVS to '|| v_role);
      execute_stmt('GRANT ' || priv_type || ' ON SYS.DBA_ROLE_PRIVS to '|| v_role);
	  execute_object_grant('SYS', 'AUDIT_ACTIONS', v_role, priv_type);
	  execute_stmt('GRANT ' || priv_type || ' ON SYS.DBA_SCHEDULER_JOB_RUN_DETAILS to '|| v_role);

        IF (v_con_id=1)
        THEN
            execute_stmt('GRANT '||priv_type||' ON SYS.V_$PARAMETER TO ' || v_role);
        END IF;

        IF (ver >= '18%')
        THEN
          	execute_stmt('GRANT EXECUTE ON AUDSYS.DBMS_AUDIT_MGMT to '|| v_role);
       	ELSE
  		execute_stmt('GRANT EXECUTE ON SYS.DBMS_AUDIT_MGMT to '|| v_role);
       	END IF;
       		execute_stmt('GRANT ' || v_role || ' to '|| username);
  	 EXCEPTION
          WHEN OTHERS THEN
          v_code := SQLCODE;
          v_errm := SUBSTR(SQLERRM, 1, 64);
          IF(dv='TRUE' and ver >= '23.0.0.0%')
          THEN
              IF(v_code = -47401)
                THEN
                  v_dv_errmsg := v_errm;
                  v_dv_issue := 'TRUE';
              ELSE RAISE;
              END IF;
          ELSE RAISE;
          END IF;
     END;
  	END IF;

    IF (v_type = 'REVOKE')
    THEN
      print_revoke_message('AUDIT_COLLECTION', username);
      BEGIN
        execute_stmt('REVOKE ' || v_role || ' FROM '||username);
        EXCEPTION
        WHEN OTHERS THEN
          v_code := SQLCODE;
          IF(v_code = -1919)
            THEN NULL;
          ELSE RAISE;
          END IF;
      END;
    END IF;
  END;


  PROCEDURE execute_audit_setting_mode(username VARCHAR2) AS
  BEGIN
    IF (ver <= '12.1.0.3%')
    THEN
       v_warning_audit := 'WARNING: Audit Setting mode is not supported for Oracle DB Version '||ver;

  	   IF (v_mode ='AUDIT_SETTING')
  	   THEN
  	      return;
  	   END IF;
    ELSE
       execute_enquote_role_name(role_prefix, 'AUDIT_SETTING');
  	   IF (v_type = 'GRANT')
  	   THEN
          sys.dbms_output.new_line();
  	      sys.dbms_output.put_line('Granting AUDIT_SETTING privileges to '|| username ||' ... ');
          create_role('AUDIT_SETTING');
  	      execute_stmt('GRANT CREATE SESSION  to '|| v_role);
          grant_audit_admin(v_role, 'SELECT');

          execute_object_grant('SYS','DUAL', v_role, 'SELECT');
          execute_object_grant('SYS','SESSION_ROLES', v_role, 'SELECT');
          execute_object_grant('SYS','SESSION_PRIVS', v_role, 'SELECT');
          execute_object_grant('SYS','ALL_TAB_PRIVS', v_role, 'SELECT');
          execute_object_grant('SYS','DBMS_STANDARD', v_role, 'EXECUTE');
          execute_object_grant('SYS','PRODUCT_COMPONENT_VERSION', v_role, 'SELECT');
          IF (v_con_id=1)
          THEN
            execute_stmt('GRANT READ ON SYS.V_$PARAMETER TO ' || v_role);
          END IF;
          execute_stmt('GRANT ' || v_role || ' to '|| username);
  	   END IF;
  	   IF (v_type = 'REVOKE')
  	   THEN
  	      print_revoke_message('AUDIT_SETTING', username);
  	      BEGIN
  	        execute_stmt('REVOKE ' || v_role || ' FROM '||username);
          EXCEPTION
            WHEN OTHERS THEN
            v_code := SQLCODE;
            IF(v_code = -1919)
              THEN NULL;
            ELSE RAISE;
            END IF;
          END;
  	   END IF;
    END IF;
  END; -- End procedure execute_audit_setting_mode

  PROCEDURE execute_sql_firewall_mode(username VARCHAR2) AS
    BEGIN
      IF (ver < '23.0.0.0%')
      THEN
         v_warning_audit := 'WARNING: SQL firewall is not supported for Oracle DB Version '||ver;

    	   IF (v_mode ='SQL_FIREWALL')
    	   THEN
    	      return;
    	   END IF;
      ELSE
          execute_enquote_role_name(role_prefix, 'SQL_FIREWALL');
    	   IF (v_type = 'GRANT')
    	   THEN
    	      sys.dbms_output.put_line('Granting SQL_FIREWALL privileges to '|| username ||' ... ');
            create_role('SQL_FIREWALL');
    	    execute_stmt('GRANT CREATE SESSION  to '|| v_role);
            execute_stmt('GRANT AUDIT_ADMIN TO '|| v_role);
            execute_stmt('GRANT SQL_FIREWALL_ADMIN TO '|| v_role);

          execute_object_grant('SYS','SESSION_ROLES', v_role, 'SELECT');
          execute_object_grant('SYS','SESSION_PRIVS', v_role, 'SELECT');
          execute_object_grant('SYS','ALL_TAB_PRIVS', v_role, 'SELECT');
          execute_object_grant('SYS','PRODUCT_COMPONENT_VERSION', v_role, 'SELECT');

            IF (v_con_id=1)
            THEN
               execute_object_grant('SYS', 'V_$PARAMETER', v_role, 'READ');
            END IF;
            execute_stmt('GRANT ' || v_role || ' to '|| username);
    	   END IF;
    	   IF (v_type = 'REVOKE')
    	   THEN
    	      print_revoke_message('SQL_FIREWALL', username);
    	      BEGIN
    	      execute_stmt('REVOKE ' || v_role || ' FROM '||username);
            EXCEPTION
              WHEN OTHERS THEN
              v_code := SQLCODE;
              IF(v_code = -1919)
                THEN NULL;
              ELSE RAISE;
              END IF;
            END;
    	   END IF;
      END IF;
    END; -- End procedure execute_sql_firewall_mode

  PROCEDURE execute_data_discovery_mode(username VARCHAR2) AS
  v_role_name varchar2(128);
  BEGIN
    IF (ver >= '12.1.0.2%')
    THEN
       priv_type := 'READ';
    ELSE
       priv_type := 'SELECT';
    END IF;
    v_role_name := role_prefix || 'DATA_DISCOVERY';
    /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
    revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
    v_sql := 'begin ' ||
          ':v_role := sys.dbms_assert.enquote_name(:v_role_name, FALSE);' ||
          ' end;';
    execute immediate v_sql using out v_role, in v_role_name;
    IF (v_type = 'GRANT')
    THEN
       sys.dbms_output.new_line();
       sys.dbms_output.put_line('Granting DATA_DISCOVERY role to '|| username ||' ... ');
       create_role('DATA_DISCOVERY');
       execute_stmt('GRANT CREATE SESSION TO ' || v_role );
       execute_stmt('GRANT ' || priv_type || ' ANY TABLE TO ' || v_role);
       execute_stmt('GRANT CREATE PROCEDURE TO '|| v_role);
       execute_object_grant('SYS','V_$DATABASE', v_role, priv_type);
       execute_object_grant('SYS','ALL_COL_COMMENTS', username, priv_type);
       execute_object_grant('SYS','ALL_CONSTRAINTS', username, priv_type);
       execute_object_grant('SYS','ALL_CONS_COLUMNS', username, priv_type);
       execute_object_grant('SYS','ALL_EDITIONING_VIEWS', username, priv_type);
       execute_object_grant('SYS','ALL_MVIEWS', username, priv_type);
       execute_object_grant('SYS','ALL_OBJECT_TABLES', username, priv_type);
       execute_object_grant('SYS','ALL_OBJECTS', username, priv_type);
       execute_object_grant('SYS','ALL_QUEUE_TABLES', username, priv_type);
       execute_object_grant('SYS','ALL_USERS', username, priv_type);
       execute_object_grant('SYS','ALL_SNAPSHOT_LOGS', username, priv_type);
       execute_object_grant('SYS','ALL_TABLES', username, priv_type);
       execute_object_grant('SYS','ALL_TAB_COLUMNS', username, priv_type);
       execute_object_grant('SYS','DBMS_DB_VERSION', username, 'EXECUTE');
       execute_object_grant('SYS','DBMS_SQL', username, 'EXECUTE');
       execute_object_grant('SYS','DBMS_LOB', username, 'EXECUTE');
       execute_object_grant('SYS','DBMS_STANDARD', username, 'EXECUTE');
       execute_object_grant('SYS','DUAL', username, 'SELECT');
       execute_object_grant('SYS','PLITBLM', v_role, 'EXECUTE');
       execute_object_grant('SYS','PRODUCT_COMPONENT_VERSION', username, priv_type);
       execute_object_grant('SYS','SESSION_PRIVS', username, priv_type);
       execute_object_grant('SYS','SESSION_ROLES', v_role, priv_type);
       execute_object_grant('SYS','USER_TAB_PRIVS', v_role, priv_type);
       execute_object_grant('SYS','XMLSEQUENCE', username, 'EXECUTE');
       execute_object_grant('SYS','XMLSEQUENCETYPE', username, 'EXECUTE');
       execute_object_grant('SYS','XMLTYPE', username, 'EXECUTE');
       execute_object_grant('SYS','XQSEQUENCE', username, 'EXECUTE');
       IF (NOT v_is_rdsfororacle)
       THEN
          execute_object_grant('SYS','DBMS_ASSERT', username, 'EXECUTE');
          execute_object_grant('SYS','DBMS_OUTPUT', username, 'EXECUTE');
       END IF;
    IF (ver >= '12.1.0.2%')
    THEN
        execute_object_grant('SYS','ALL_JSON_COLUMNS', username, priv_type);
    END IF;
    IF (ver > '12.2%')
    THEN
       execute_object_grant('SYS','JSON_ARRAY_T', username, 'EXECUTE');
       execute_object_grant('SYS','JSON_OBJECT_T', username, 'EXECUTE');
    END IF;
       -- grant role to user
       execute_stmt('GRANT ' || v_role || ' to '|| username);
    END IF;
    IF (v_type = 'REVOKE')
    THEN
       print_revoke_message('DATA_DISCOVERY', username);
       BEGIN
         BEGIN
           IF (NOT v_is_rdsfororacle)
           THEN
             revoke_object_grant('SYS','DBMS_ASSERT', v_user, 'EXECUTE');
             revoke_object_grant('SYS','DBMS_OUTPUT', v_user, 'EXECUTE');
           END IF;
         EXCEPTION
           WHEN OTHERS THEN
             v_code := SQLCODE;
             IF(v_code = -1927)
             /* Suppressing the error in case of multiple revoke runs */
               THEN NULL;
             ELSE
               RAISE;
             END IF;
         END;
       execute_stmt('REVOKE ' || v_role || ' FROM '||username);
       revoke_object_grant('SYS','ALL_CONSTRAINTS', username, priv_type);
       revoke_object_grant('SYS','ALL_CONS_COLUMNS', username, priv_type);
       revoke_object_grant('SYS','ALL_EDITIONING_VIEWS', username, priv_type);
       revoke_object_grant('SYS','ALL_MVIEWS', username, priv_type);
       revoke_object_grant('SYS','ALL_OBJECT_TABLES', username, priv_type);
       revoke_object_grant('SYS','ALL_SNAPSHOT_LOGS', username, priv_type);
       revoke_object_grant('SYS','ALL_TABLES', username, priv_type);
       revoke_object_grant('SYS','ALL_TAB_COLUMNS', username, priv_type);
       revoke_object_grant('SYS','ALL_USERS', username, priv_type);
       revoke_object_grant('SYS','ALL_OBJECTS', username, priv_type);
       revoke_object_grant('SYS','DBMS_DB_VERSION', username, 'EXECUTE');
       revoke_object_grant('SYS','DBMS_SQL', username, 'EXECUTE');
       revoke_object_grant('SYS','DBMS_STANDARD', username, 'EXECUTE');
       revoke_object_grant('SYS','DUAL', username, 'SELECT');
       revoke_object_grant('SYS','PRODUCT_COMPONENT_VERSION', username, priv_type);
       revoke_object_grant('SYS','XMLSEQUENCE', username, 'EXECUTE');
       revoke_object_grant('SYS','XMLSEQUENCETYPE', username, 'EXECUTE');
       revoke_object_grant('SYS','XMLTYPE', username, 'EXECUTE');
       revoke_object_grant('SYS','DBMS_LOB', username, 'EXECUTE');
       revoke_object_grant('SYS','XQSEQUENCE', username, 'EXECUTE');
       revoke_object_grant('SYS','ALL_COL_COMMENTS', username, priv_type);
       revoke_object_grant('SYS','SESSION_PRIVS', username, priv_type);
       revoke_object_grant('SYS','ALL_QUEUE_TABLES', username, priv_type);
       IF (ver >= '12.1.0.2%')
       THEN
            revoke_object_grant('SYS','ALL_JSON_COLUMNS', username, priv_type);
       END IF;
       IF (ver >= '12.2%')
       THEN
            revoke_object_grant('SYS','JSON_ARRAY_T', username, 'EXECUTE');
            revoke_object_grant('SYS','JSON_OBJECT_T', username, 'EXECUTE');
       END IF;
       EXCEPTION
         WHEN OTHERS THEN
           v_code := SQLCODE;
           IF(v_code = -1919)
             THEN NULL;
           ELSE RAISE;
           END IF;
       END;
    END IF;
  END; -- End procedure execute_data_discovery_mode


  PROCEDURE execute_assessment_mode(username VARCHAR2) AS
  BEGIN
    IF (ver >= '12.1.0.2%')
    THEN
       priv_type := 'READ';
    ELSE
       priv_type := 'SELECT';
    END IF;
    v_role := sys.dbms_assert.enquote_name(role_prefix || 'ASSESSMENT', FALSE);
    IF (v_type = 'GRANT')
    THEN
    BEGIN
      sys.dbms_output.new_line();
      sys.dbms_output.put_line('Granting ASSESSMENT role to '|| username ||' ... ');
      create_role('ASSESSMENT');
      execute_stmt('GRANT CREATE SESSION TO '|| v_role);
      execute_object_grant('SYS', 'DBMS_LOB', v_role, 'EXECUTE');
      execute_object_grant('SYS', 'DBMS_SQL', v_role, 'EXECUTE');
      execute_object_grant('SYS', 'DBA_ROLES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_ROLE_PRIVS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_SYS_PRIVS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_TAB_PRIVS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_TABLES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_COL_PRIVS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_USERS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_PROFILES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_DIRECTORIES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_DB_LINKS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_DATA_FILES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_TRIGGERS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_POLICIES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_ENCRYPTED_COLUMNS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_LIBRARIES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_NETWORK_ACLS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_NETWORK_ACL_PRIVILEGES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_STMT_AUDIT_OPTS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_OBJ_AUDIT_OPTS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_PRIV_AUDIT_OPTS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_AUDIT_POLICIES', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_AUDIT_TRAIL', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_FGA_AUDIT_TRAIL', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_CONSTRAINTS', v_role, priv_type);
      execute_object_grant('SYS', 'V_$INSTANCE', v_role, priv_type);
      execute_object_grant('SYS', 'V_$VERSION', v_role, priv_type);
      execute_object_grant('SYS', 'V_$OPTION', v_role, priv_type);
      execute_object_grant('SYS', 'V_$PWFILE_USERS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_TAB_COLUMNS', v_role, priv_type);
      execute_object_grant('SYS', 'V_$DATABASE', v_role, priv_type);
      execute_object_grant('SYS', 'V_$PARAMETER', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_REGISTRY_HISTORY', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_SEC_RELEVANT_COLS', v_role, priv_type);
      execute_object_grant('SYS', 'REDACTION_POLICIES', v_role, priv_type);
      execute_object_grant('SYS', 'REDACTION_COLUMNS', v_role, priv_type);
      execute_object_grant('SYS', 'V_$ENCRYPTION_WALLET', v_role, priv_type);
      execute_object_grant('SYS', 'V_$ENCRYPTED_TABLESPACES', v_role, priv_type);
      execute_object_grant('SYS', 'V_$TABLESPACE', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_SOURCE', v_role, priv_type);
      execute_object_grant('SYS', 'GV_$SESSION', v_role, priv_type);
      execute_object_grant('SYS', 'GV_$SESSION_CONNECT_INFO', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_VIEWS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_DEPENDENCIES', v_role, priv_type);
      execute_object_grant('SYS', 'DBMS_SQLHASH', v_role, 'EXECUTE');
      execute_object_grant('SYS', 'DBA_AUDIT_MGMT_CONFIG_PARAMS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_AUDIT_MGMT_CLEANUP_JOBS', v_role, priv_type);
      execute_object_grant('SYS', 'PROXY_USERS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_OBJECTS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_REGISTRY', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_FEATURE_USAGE_STATISTICS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_FREE_SPACE', v_role, priv_type);
      execute_object_grant('SYS', 'V_$CONTROLFILE', v_role, priv_type);
      execute_object_grant('SYS', 'V_$LOG', v_role, priv_type);
      execute_object_grant('SYS', 'V_$LOGFILE', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_JOBS', v_role, priv_type);
      execute_object_grant('SYS', 'DBA_PROCEDURES', v_role, priv_type);
      execute_object_grant('SYS', 'ALL_SCHEDULER_GLOBAL_ATTRIBUTE', v_role, priv_type);
      execute_object_grant('SYS', 'V_$WALLET', v_role, priv_type);
      -- grants used from PUBLIC DS-38210
      execute_object_grant('SYS', 'PLITBLM', v_role, 'EXECUTE');
      execute_object_grant('SYS', 'XMLTYPE', v_role, 'EXECUTE');
      execute_object_grant('SYS', 'DUAL', v_role, priv_type);
      execute_object_grant('SYS', 'ALL_USERS', v_role, priv_type);
      execute_object_grant('SYS', 'PRODUCT_COMPONENT_VERSION', v_role, priv_type);

      IF check_view_exists('SYS', 'DBA_REPCATLOG') THEN
          execute_object_grant('SYS', 'DBA_REPCATLOG', v_role, priv_type);
      END IF;

      IF check_view_exists('CTXSYS', 'CTX_INDEXES') THEN
          execute_stmt('GRANT '||priv_type||' ON CTXSYS.CTX_INDEXES TO ' || v_role);
      END IF;

      -- SYS.SCHEDULER$_DBMSJOB_MAP is created in 19c
      BEGIN
          execute_object_grant('SYS', 'SCHEDULER$_DBMSJOB_MAP', v_role, priv_type);
      EXCEPTION
        WHEN OTHERS THEN
          IF SQLCODE IN ( -942) THEN NULL; --ignore table not exist
          ELSE RAISE;
          END IF;
      END;

      IF (ver >= '12.1%' and check_view_exists('SYS', 'DBA_DV_STATUS') and check_user_exists('DVSYS')) THEN
        execute_object_grant('SYS', 'DBA_DV_STATUS', v_role, priv_type);
      END IF;

      -- SELECT_CATALOG_ROLE is needed to query DBA_DV_STATUS before 20.1
      IF (ver <= '20.1%')
      THEN
         execute_stmt('GRANT SELECT_CATALOG_ROLE TO ' || v_role);
      END IF;

      -- we do not need following two privileges for ADW/ATP-S as we dont show these findings for those targets
      IF v_targetType is null OR upper(v_targetType) NOT IN ('OLTP', 'PAAS', 'DWCS' , 'JDCS')
      THEN
        execute_object_grant('SYS', 'V_$RMAN_STATUS', v_role, priv_type);
	    execute_object_grant('SYS', 'V_$BACKUP_PIECE', v_role, priv_type);
      END IF;

      IF (ver >= '12.1%')
      THEN
	    execute_object_grant('SYS', 'DBA_REGISTRY_SQLPATCH', v_role, 'SELECT');
	    execute_object_grant('SYS', 'DBA_SENSITIVE_DATA', v_role, 'SELECT');
	    execute_object_grant('SYS', 'DBA_TSDP_POLICY_FEATURE', v_role, 'SELECT');
	    execute_object_grant('SYS', 'DBA_XS_POLICIES', v_role, 'SELECT');
        execute_object_grant('SYS', 'DBA_XS_APPLIED_POLICIES', v_role, 'SELECT');
	    execute_object_grant('SYS', 'DBA_XS_ACES', v_role, 'SELECT');
	    execute_object_grant('SYS', 'V_$CONTAINERS', v_role, 'SELECT');
	    execute_object_grant('SYS', 'DBA_CODE_ROLE_PRIVS', v_role, 'SELECT');
     END IF;

     IF (ver >= '23.0.0.0%')
     THEN
       execute_object_grant('SYS', 'DBA_SCHEMA_PRIVS', v_role, priv_type);
       execute_object_grant('SYS', 'DBA_SQL_FIREWALL_STATUS', v_role, priv_type);
       execute_object_grant('SYS', 'DBA_SQL_FIREWALL_ALLOW_LISTS', v_role, priv_type);
     END IF;

    EXCEPTION
            WHEN OTHERS THEN
            v_code := SQLCODE;
            v_errm := SUBSTR(SQLERRM, 1, 64);
            IF(dv='TRUE' and ver >= '23.0.0.0%')
            THEN
                IF(v_code = -47401)
                  THEN
                    v_dv_errmsg := v_errm;
                    v_dv_issue := 'TRUE';
                ELSE RAISE;
                END IF;
            ELSE RAISE;
            END IF;
       END;

     BEGIN
	   execute_object_grant('SYS', '"_BASE_USER"', v_role, priv_type);
     EXCEPTION
       WHEN OTHERS THEN NULL;
     END;

     BEGIN
	   execute_object_grant('SYS', 'REGISTRY$HISTORY', v_role, priv_type);
       execute_object_grant('SYS', 'DBA_USERS_WITH_DEFPWD', v_role, priv_type);
	   execute_object_grant('SYS', 'DBA_JAVA_POLICY', v_role, priv_type);

          --grants on objects not in any Default realm should be added before this.
	   IF check_user_exists('LBACSYS') THEN
	     IF check_view_exists('LBACSYS', 'DBA_SA_SCHEMA_POLICIES') THEN
           execute_stmt('GRANT '||priv_type||' ON LBACSYS.DBA_SA_SCHEMA_POLICIES  TO ' || v_role);
	     END IF;

	     IF check_view_exists('LBACSYS', 'DBA_SA_TABLE_POLICIES') THEN
           execute_stmt('GRANT '||priv_type||' ON LBACSYS.DBA_SA_TABLE_POLICIES TO ' || v_role);
	     END IF;

         IF check_view_exists('LBACSYS', 'DBA_SA_AUDIT_OPTIONS') THEN
           execute_stmt('GRANT '||priv_type||' ON LBACSYS.DBA_SA_AUDIT_OPTIONS TO ' || v_role);
         END IF;

         IF (ver >= '12.1%' and check_view_exists('LBACSYS', 'DBA_OLS_STATUS'))
         THEN
           execute_stmt('GRANT '||priv_type||' ON LBACSYS.DBA_OLS_STATUS TO ' || v_role);
         END IF;
       END IF;

       IF (dv='FALSE' and check_user_exists('DVSYS'))
       THEN
         IF check_view_exists('DVSYS', 'DBA_DV_REALM_OBJECT') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_REALM_OBJECT TO ' || v_role);
         END IF;

         IF check_view_exists('DVSYS', 'DBA_DV_REALM') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_REALM TO ' || v_role);
         END IF;

         IF check_view_exists('DVSYS', 'DBA_DV_COMMAND_RULE') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_COMMAND_RULE TO ' || v_role);
         END IF;

         IF check_view_exists('DVSYS', 'DBA_DV_RULE_SET') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_RULE_SET TO ' || v_role);
         END IF;

         IF check_view_exists('DVSYS', 'DBA_DV_FACTOR') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_FACTOR TO ' || v_role);
         END IF;

         IF check_view_exists('DVSYS', 'DBA_DV_STATUS') THEN
           execute_stmt('GRANT '||priv_type||' ON DVSYS.DBA_DV_STATUS TO ' || v_role);
         END IF;
       END IF;

     EXCEPTION
     WHEN OTHERS THEN
       v_code := SQLCODE;
       IF(v_code = -47401)
       THEN
         -- DV_SECANALYST has the select privilege on DBA_DV_REALM_OBJECT,
         -- DBA_DV_REALM and DBA_DV_COMMAND_RULE. We already printed the message to ask
         -- customer to grant DV_SECANALYST to the DataSafe user. The DataSafe user should get
         -- read access to DBA_DV_REALM/REALM_OBJECT/COMMAND_RULE through DV_SECANALYST,
         -- not object privilege grants.
         -- Note, before 23c, 'Oracle Database Vault' realm which protects DVSYS schema
         -- is a regular realm. After 23c, it is a mandatory realm but DV_SECANALYST is
         -- also authorized to this realm by default, so DV_SECANALYST would still be
         -- enough for the DataSafe user to access these three DV views.
         -- The following message is mainly for LBACSYS views.
         v_assessWarning := chr(13) || chr(10) ||
           'Check the DV Realm that are protecting LBACSYS schema. ' || chr(13) || chr(10) ||
           chr(13) || chr(10) ||
           'Connect to the secured target database as DV_OWNER and execute: ' || chr(13) || chr(10) ||
           'select distinct realm_name from dvsys.dba_dv_realm_object where owner=''LBACSYS'';' ||
           chr(13) || chr(10) || chr(13) || chr(10) ||
           'Temporarily authorize SYS as an owner to the Realm ' ||
           'and perform the following grants using SYS.' || chr(13) || chr(10) || chr(13) || chr(10) ||
           'Connect to the secured target database as DV_OWNER and execute: ' || chr(13) || chr(10) ||
           'exec dbms_macadm.add_auth_to_realm(''<realm_name>'',''SYS'', DBMS_MACUTL.G_REALM_AUTH_OWNER);' ||
           chr(13) || chr(10) ||
           'Connect to the secured target database as SYS and execute: ' || chr(13) || chr(10) ||
           'GRANT '||priv_type||' ON LBACSYS.DBA_SA_SCHEMA_POLICIES'||
           ' TO ' || v_role || ';'|| chr(13) || chr(10) ||
           'GRANT '||priv_type||' ON LBACSYS.DBA_SA_TABLE_POLICIES'||
           ' TO ' || v_role || ';' || chr(13) || chr(10);

           IF (ver >= '12.1')
           THEN
             v_assessWarning := v_assessWarning ||
             'GRANT '||priv_type||' ON LBACSYS.DBA_OLS_STATUS'||
             ' TO ' || v_role || ';' || chr(13) || chr(10);
           END IF;

           v_assessWarning := v_assessWarning || chr(13) || chr(10) ||
             'Remember to remove the newly given Realm authorization after you have run the privilege script ' ||
             'successfully without errors.' ||chr(13) || chr(10) ||
             'Connect to the secured target database as DV_OWNER user and execute: ' || chr(13) || chr(10) ||
             'exec dbms_macadm.delete_auth_from_realm(''<realm_name>'',''SYS'');' ||
             chr(13) || chr(10) || chr(13) || chr(10);

           IF (ver >= '23.0%')
           THEN
             v_assessWarning := v_assessWarning ||
             'Please note that starting from 23c, the DV Realms that are protecting LBACSYS and DVSYS ' ||
             'are mandatory realms, so please make sure the user - ' || username ||
             ' is also authorized (or is granted with role that is authorized) to these realms.' || chr(13) || chr(10) ||
             '(Note that starting from 23c, DV_SECANALYST is already by default authorized ' ||
             'to the ''Oracle Database Vault'' Realm.)' || chr(13) || chr(10) || chr(13) || chr(10) ||
             'Connect to the secured target database as DV_OWNER user and execute: ' || chr(13) || chr(10) ||
             'exec dbms_macadm.add_auth_to_realm(''<realm_name>'','''|| username||''');' || chr(13) || chr(10);
           END IF;

           IF(dv='TRUE' and ver >= '23.0.0.0%')
           THEN
             v_errm := SUBSTR(SQLERRM, 1, 64);
             v_dv_errmsg := v_errm;
             v_dv_issue := 'TRUE';
           END IF;
       ELSIF(v_code = -942 OR v_code = -1031)
       THEN NULL;
       ELSE
         RAISE;
       END IF;
     END;

     IF (ver >= '12.1%')
     THEN
       grant_audit_viewer(v_role, 'SELECT');
       execute_stmt('GRANT CAPTURE_ADMIN TO '|| v_role);
       BEGIN
         execute_stmt('GRANT SELECT ON AUDSYS.AUD$UNIFIED TO '|| v_role);
       EXCEPTION
       WHEN OTHERS THEN
         v_code := SQLCODE;
         IF(v_code = -942 OR v_code = -1031)
         THEN NULL;
         ELSIF(v_code = -47401)
         THEN
           v_errm := SUBSTR(SQLERRM, 1, 64);
           IF(dv='TRUE' and ver >= '23.0.0.0%')
           THEN
             v_dv_errmsg := v_errm;
             v_dv_issue := 'TRUE';
           ELSE RAISE;
           END IF;
         ELSE
           RAISE;
         END IF;
       END;
     END IF;
     -- grant role to user
     execute_stmt('GRANT ' || v_role || ' to '|| username);
    ELSE
      sys.dbms_output.new_line();
      sys.dbms_output.put_line('Revoking ASSESSMENT role from '||username||' ... ');
      BEGIN
        execute_stmt('REVOKE ' || v_role || ' FROM '||username);
      EXCEPTION
      WHEN OTHERS THEN
        v_code := SQLCODE;
        IF(v_code = -1919)
        THEN NULL;
        ELSE
          RAISE;
        END IF;
      END;
    END IF;
  END;  --End procedure execute_assessment_mode


  PROCEDURE execute_masking_mode(username VARCHAR2) AS
  v_role_name varchar2(128);
  BEGIN
    IF (ver >= '12.1.0.2%')
    THEN
        priv_type := 'READ';
    ELSE
        priv_type := 'SELECT';
    END IF;
    v_role_name := role_prefix || 'MASKING';
    /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
    revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
     v_sql := 'begin ' ||
          ':v_role := sys.dbms_assert.enquote_name(:v_role_name, FALSE);' ||
          ' end;';
     execute immediate v_sql using out v_role, in v_role_name;
     IF (v_type = 'GRANT')
     THEN
        sys.dbms_output.new_line();
        sys.dbms_output.put_line('Granting MASKING role to '|| username ||' ... ');
        EXECUTE IMMEDIATE ('select DEFAULT_TABLESPACE from '||
                           'SYS.DBA_USERS where USERNAME = :1')
                            into v_tableSpace
                            using sys.dbms_assert.schema_name(v_user);

        IF (v_tableSpace = 'SYSTEM' OR v_tableSpace = 'SYSAUX')
        THEN
           v_warning := 'WARNING : Default tablespace of the user is SYSTEM/SYSAUX.'||
                       ' Masking job by users with either of these as default tablespace will fail.';
        END IF;

        create_role('MASKING');
        execute_stmt('GRANT CREATE SESSION TO ' || v_role);
        -- *** SELECT_CATALOG_ROLE Required for DBMS_METADATA call
        execute_stmt('GRANT SELECT_CATALOG_ROLE TO ' || v_role);
        execute_stmt('GRANT SELECT ANY TABLE TO ' || v_role);
        execute_stmt('GRANT CREATE ANY PROCEDURE TO ' || v_role);
        execute_stmt('GRANT DROP ANY PROCEDURE TO ' || v_role);
        execute_stmt('GRANT EXECUTE ANY PROCEDURE TO ' || v_role);
        execute_stmt('GRANT ANALYZE ANY TO ' || v_role);
        execute_stmt('GRANT SELECT ANY SEQUENCE TO ' || v_role);

        -- Dont grant alter system, alter database for cloud targets
        IF v_targetType is null OR upper(v_targetType) NOT IN ('OLTP', 'PAAS', 'DWCS', 'JDCS')
        THEN
  	      IF (NOT v_is_rdsfororacle)
  	      THEN
	   	    execute_stmt('GRANT ALTER SYSTEM TO ' || v_role);
	      END IF;
        END IF;

        execute_stmt('GRANT CREATE TYPE TO ' || v_role);
        execute_stmt('GRANT CREATE ANY TABLE TO ' || v_role);
        execute_stmt('GRANT INSERT ANY TABLE TO ' || v_role);
        execute_stmt('GRANT LOCK ANY TABLE TO ' || v_role);
        execute_stmt('GRANT ALTER ANY TABLE TO ' || v_role);
        execute_stmt('GRANT DROP ANY TABLE TO ' || v_role);
        execute_stmt('GRANT UPDATE ANY TABLE TO ' || v_role);
        execute_stmt('GRANT CREATE ANY INDEX TO ' || v_role);
        execute_stmt('GRANT DROP ANY INDEX TO ' || v_role);
        execute_stmt('GRANT ALTER ANY INDEX TO ' || v_role);
        execute_stmt('GRANT COMMENT ANY TABLE TO ' || v_role);
        execute_stmt('GRANT CREATE ANY TRIGGER TO ' || v_role);
        execute_stmt('GRANT DROP ANY TRIGGER TO ' || v_role);
        execute_stmt('GRANT ALTER ANY TRIGGER TO ' || v_role);
        execute_stmt('GRANT DROP ANY SEQUENCE TO ' || v_role);

        execute_object_grant('SYS','PRODUCT_COMPONENT_VERSION', v_user, priv_type);
        execute_object_grant('SYS','DUAL', v_user, 'SELECT');
        -- Required for deterministic mask
        execute_stmt('GRANT CREATE ANY CONTEXT TO ' || v_role);
        execute_stmt('GRANT DROP ANY CONTEXT TO ' || v_role);
        --Explicitly added Privileges
        IF (ver >= '12.1.0.2%')
        THEN
            execute_object_grant('SYS','ALL_JSON_COLUMNS', v_user, priv_type);
        END IF;
        execute_object_grant('SYS','ALL_TAB_COLS', v_role, priv_type);
        execute_object_grant('SYS','CREATE_TABLE_COST_COLINFO', username, 'EXECUTE');
        execute_object_grant('SYS','CREATE_TABLE_COST_COLUMNS', username, 'EXECUTE');
        execute_object_grant('SYS','DBA_EDITIONING_VIEW_COLS', v_role, priv_type);
        execute_object_grant('SYS','ALL_CONSTRAINTS', v_role, priv_type);
        execute_object_grant('SYS','ALL_COL_COMMENTS', v_role, priv_type);
        execute_object_grant('SYS','ALL_EDITIONING_VIEWS', v_role, priv_type);
        execute_object_grant('SYS','ALL_MVIEWS', v_role, priv_type);
        execute_object_grant('SYS','ALL_QUEUE_TABLES', v_role, priv_type);
        execute_object_grant('SYS','ALL_SNAPSHOT_LOGS', v_role, priv_type);
        execute_object_grant('SYS','ALL_TAB_COLUMNS', v_role, priv_type);
        execute_object_grant('SYS','DBMS_LOB', username, 'EXECUTE');
        execute_object_grant('SYS','DBMS_METADATA', username, 'EXECUTE');
        execute_object_grant('SYS','DBMS_RANDOM', username, 'EXECUTE');
        execute_object_grant('SYS','DBMS_STATS', username, 'EXECUTE');
        execute_object_grant('SYS','DBMS_UTILITY', username, 'EXECUTE');
        execute_object_grant('SYS','DBMS_SQL', username, 'EXECUTE');
        execute_object_grant('SYS','KU$_HTABLE_VIEW', v_role, priv_type);
        execute_object_grant('SYS','KU$_INDEX_VIEW', v_role, priv_type);
        execute_object_grant('SYS','KU$_PFHTABPROP_VIEW', v_role, priv_type);
        execute_object_grant('SYS','KU$_REFPARTTABPROP_VIEW', v_role, priv_type);
        execute_object_grant('SYS','KU$_TRIGGER_VIEW', v_role, priv_type);
        execute_object_grant('SYS','KU$_TABPROP_VIEW', v_role, priv_type);
        execute_object_grant('SYS','NLS_DATABASE_PARAMETERS', v_role, priv_type);
        execute_object_grant('SYS','NLS_SESSION_PARAMETERS', v_role, priv_type);
        execute_object_grant('SYS','PLITBLM', v_role, 'EXECUTE');
        execute_object_grant('SYS','SESSION_PRIVS', v_role, priv_type);
        execute_object_grant('SYS','SESSION_ROLES', v_role, priv_type);
        execute_object_grant('SYS','USER_TAB_PRIVS', v_role, priv_type);
        execute_object_grant('SYS','USER_USERS', username, priv_type);
        execute_object_grant('SYS','XMLGENFORMATTYPE', username, 'EXECUTE');
        execute_object_grant('SYS','XMLTYPE', username, 'EXECUTE');
        execute_object_grant('SYS','XQSEQUENCE', username, 'EXECUTE');
        IF (NOT v_is_rdsfororacle)
        THEN
          execute_object_grant('SYS','DBMS_ASSERT', username, 'EXECUTE');
          execute_object_grant('SYS','DBMS_OUTPUT', username, 'EXECUTE');
        END IF;
        -- Direct grants required since roles are turned off during
        -- pl/sql code compilation. Our deploy will fail without this.
        execute_object_grant('SYS','DBMS_CRYPTO', username, 'EXECUTE');
        execute_object_grant('SYS','UTL_RECOMP', username, 'EXECUTE');
        -- DS-34729: Below privilege is required for 23ai version, because
        -- CTXSYS is dictionary protected schema
        IF (ver >= '23.0.0%')
        THEN
            execute_stmt('GRANT EXECUTE ON CTXSYS.CTX_DDL TO ' || username);
        END IF;
        execute_stmt('GRANT UNLIMITED TABLESPACE TO '||username);

        -- grant role to user
        execute_stmt('GRANT ' || v_role || ' to '|| username);
     END IF;
     IF (v_type = 'REVOKE')
     THEN
        print_revoke_message('MASKING', username);
        BEGIN
          IF (NOT v_is_rdsfororacle)
          THEN
            revoke_object_grant('SYS','DBMS_ASSERT', username, 'EXECUTE');
            revoke_object_grant('SYS','DBMS_OUTPUT', username, 'EXECUTE');
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            v_code := SQLCODE;
            IF(v_code = -1927)
            /* Suppressing the error in case of multiple revoke runs and also
            during the flow of revoke ALL since it is already being done in DATA_DISCOVERY */
              THEN NULL;
            ELSE
              RAISE;
            END IF;
        END;
        execute_stmt('REVOKE UNLIMITED TABLESPACE from '||username);
        revoke_object_grant('SYS','DBMS_CRYPTO', username, 'EXECUTE');
        revoke_object_grant('SYS','UTL_RECOMP', username, 'EXECUTE');
        IF (ver >= '23.0.0%')
        THEN
            execute_stmt('REVOKE EXECUTE ON CTXSYS.CTX_DDL FROM ' || username);
        END IF;
        revoke_object_grant('SYS','PRODUCT_COMPONENT_VERSION', username, priv_type);
        revoke_object_grant('SYS','DUAL', username, 'SELECT');
        revoke_object_grant('SYS','CREATE_TABLE_COST_COLINFO', username, 'EXECUTE');
        revoke_object_grant('SYS','CREATE_TABLE_COST_COLUMNS', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_STANDARD', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_LOB', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_METADATA', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_RANDOM', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_STATS', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_UTILITY', username, 'EXECUTE');
        revoke_object_grant('SYS','DBMS_SQL', username, 'EXECUTE');
        revoke_object_grant('SYS','USER_USERS', username, priv_type);
        revoke_object_grant('SYS','XMLGENFORMATTYPE', username, 'EXECUTE');
        revoke_object_grant('SYS','XMLTYPE', username, 'EXECUTE');
        revoke_object_grant('SYS','XQSEQUENCE', username, 'EXECUTE');
        IF (ver >= '12.1.0.2%')
        THEN
            revoke_object_grant('SYS','ALL_JSON_COLUMNS', username, priv_type);
        END IF;
        BEGIN
        execute_stmt('REVOKE ' || v_role || ' FROM '||username);
        EXCEPTION
          WHEN OTHERS THEN
          v_code := SQLCODE;
          IF(v_code = -1919)
            THEN NULL;
          ELSE RAISE;
          END IF;
        END;
     END IF;
  END; -- End procedure execute_masking_mode

BEGIN
   -- set the nls_numeric_characters to '.,' as version checking fails when nls is set to germany
   EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ''.,''';

   v_isValid := validate_input_parameters();
   IF (NOT v_isValid)
   THEN
      return;
   END IF;

   -- check if the db is pure unified auditing
   check_if_pure_unified(v_isPureUnified);

   -- check if the db is dv enabled
   if(v_dbtype is not null and v_dbtype = '-RDSORACLE') then
        dv := 'FALSE';
   else
        check_if_dv_enabled(dv);
   end if;

   -- Get the version of the database
   EXECUTE IMMEDIATE 'SELECT version FROM v$instance where regexp_like(version, ''[0-9]?[0-9].[0-9].[0-9].[0-9].[0-9]'')' into ver;

   -- Throwing error message for all modes for unsupported db versions i.e versions < 11.2.0.4
   IF(ver < '11.2.0.4%')
   THEN
      sys.dbms_output.put_line('ERROR: Oracle DB Version '||ver||' is not supported');
      sys.dbms_output.put_line('');
      sys.dbms_output.put_line('');
      return;
   END IF;

   IF(ver >= '12%')
   THEN
       -- Get if the script is run on CDB
       EXECUTE IMMEDIATE 'SELECT SYS_CONTEXT(''USERENV'', ''CON_ID'') FROM SYS.DUAL' into v_con_id;

       -- Prepend role common user prefix to role prefix if connection is CDB$ROOT
       IF (v_con_id=1)
       THEN
           SELECT value INTO v_common_user_prefix FROM v$parameter WHERE name='common_user_prefix';
           role_prefix :=  v_common_user_prefix || role_prefix;
       END IF;
   END IF;
   /* Direct invocation of dbms_assert resulted in ORA-4021 if we invoke and
   revoke in same session. Hence invoking dbms_assert indirectly via execute immediate. */
   v_sql := 'begin ' ||
          ':username := sys.dbms_assert.enquote_name(:v_user, FALSE);' ||
          ' end;';
   execute immediate v_sql using out username, in v_user;

   BEGIN
     EXECUTE IMMEDIATE ('select sys_context (''USERENV'', ''CLOUD_SERVICE'') from sys.dual') into v_targetType;
   EXCEPTION
     WHEN OTHERS THEN
       NULL;
   END;

   IF (v_mode ='AUDIT_COLLECTION' OR v_mode = 'ALL')
   THEN
      execute_audit_collection_mode(username);
   END IF;

   IF (v_mode ='AUDIT_SETTING' OR v_mode = 'ALL')
   THEN
      execute_audit_setting_mode(username);
   END IF;

   IF (v_mode ='SQL_FIREWALL' OR v_mode = 'ALL')
   THEN
    execute_sql_firewall_mode(username);
   END IF;

   IF (v_mode ='DATA_DISCOVERY' OR v_mode = 'ALL')
   THEN
      execute_data_discovery_mode(username);
   END IF;

   IF (v_mode ='MASKING' OR v_mode = 'ALL')
   THEN
      execute_masking_mode(username);
   END IF;

   IF (v_mode ='ASSESSMENT' OR v_mode = 'ALL')
   THEN
      execute_assessment_mode(username);
   END IF;
   IF (v_warning is not null)
   THEN
     sys.dbms_output.put_line(v_warning);
   END IF;
   IF (v_warning_audit is not null)
   THEN
     sys.dbms_output.put_line(v_warning_audit);
   END IF;

   execute_dv(v_type, username, v_mode, v_assessWarning);
EXCEPTION
  WHEN OTHERS THEN
     v_code := SQLCODE;
     v_errm := SUBSTR(SQLERRM, 1, 64);
     sys.DBMS_OUTPUT.PUT_LINE('The error code is ' || v_code);
     sys.dbms_output.put_line(v_errm);
     IF (v_code = -942)
     THEN
        sys.dbms_output.put_line('Login as SYS or PDB_ADMIN to grant privileges to the user ');
     END IF;
     IF (v_code != -1917)
     THEN
        sys.dbms_output.put_line('If problem persists, contact Oracle Support');
     END IF;

END;
/

SET FEEDBACK ON

EXIT;
