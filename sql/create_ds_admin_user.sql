--------------------------------------------------------------------------------
--  OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
-- Name......: create_ds_admin_user.sql
-- Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
-- Date......: 2025.07.02
-- Version...: 1.1
--
-- Purpose...: Create the Data Safe administrative user (&ds_user) in the current
--             database. Optionally drop the user if it already exists.
--             Supports setting a custom password and profile.
--
-- Usage.....: @create_ds_admin_user.sql <username> <password> <profile> <force> <update_secret>
-- Parameters:
--   &1 - Username    (default: DS_ADMIN)
--   &2 - Password    (default: empty string, must be provided if needed)
--   &3 - Profile     (default: DEFAULT)
--   &4 - Force Drop  (default: TRUE - drop user if exists)
--   &5 - Update Secret (default: FALSE - update secret if user exists)
--
-- Example....: @create_ds_admin_user.sql DS_ADMIN mySecurePW DEFAULT TRUE FALSE
--
-- Behavior...:
--   - Creates the user with the given password and profile.
--   - Drops the user first if FORCE is TRUE and user exists.
--   - Updates the user secret if UPDATE_SECRET is TRUE and user exists.
--   - Grants CONNECT and RESOURCE roles.
--   - Should be executed in CDB$ROOT with "_ORACLE_SCRIPT" enabled if needed.
--
-- Notes......:
--   - Password must follow the database password policy.
--   - This script does not enable "_ORACLE_SCRIPT"; handle this externally if
--     creating common users in CDB$ROOT.
--
-- License....: Apache License Version 2.0, January 2004
--               http://www.apache.org/licenses/
--------------------------------------------------------------------------------
-- Default parameter values ----------------------------------------------------
DEFINE _ds_user    = 'DS_ADMIN'
DEFINE _ds_passwd  = 'DS_Admin.2025'
DEFINE _ds_profile = 'DEFAULT'
DEFINE _ds_force   = 'FALSE'
DEFINE _ds_update_secret = 'FALSE'

-- Assign passed parameters or use defaults ------------------------------------
SET FEEDBACK OFF
SET VERIFY OFF
COLUMN 1 NEW_VALUE 1 NOPRINT
COLUMN 2 NEW_VALUE 2 NOPRINT
COLUMN 3 NEW_VALUE 3 NOPRINT
COLUMN 4 NEW_VALUE 4 NOPRINT
COLUMN 5 NEW_VALUE 5 NOPRINT
SELECT '' "1" FROM dual WHERE ROWNUM = 0; 
SELECT '' "2" FROM dual WHERE ROWNUM = 0; 
SELECT '' "3" FROM dual WHERE ROWNUM = 0; 
SELECT '' "4" FROM dual WHERE ROWNUM = 0; 
SELECT '' "5" FROM dual WHERE ROWNUM = 0; 
DEFINE ds_user      = &1 &_ds_user
DEFINE ds_passwd    = &2 &_ds_passwd
DEFINE ds_profile   = &3 &_ds_profile
DEFINE ds_force     = &4 &_ds_force
DEFINE ds_update_secret = &5 &_ds_update_secret

-- Configure SQLPlus -----------------------------------------------------------
SPOOL create_ds_admin_user.log
SET SERVEROUTPUT ON
SET LINESIZE 160 PAGESIZE 200

DECLARE
    -- Local types
    SUBTYPE text_type IS VARCHAR2(512 CHAR); -- NOSONAR G-2120 keep function independent

    password_reuse EXCEPTION;
    PRAGMA EXCEPTION_INIT(password_reuse, -28007);
    user_connected EXCEPTION;
    PRAGMA EXCEPTION_INIT(user_connected, -1940);

    -- Local types and variables
    l_username   dba_users.username%TYPE    := '&ds_user';
    l_passwd     dba_users.password%TYPE    := '&ds_passwd';
    l_profile    dba_users.profile%TYPE     := '&ds_profile';
    l_force      VARCHAR2(10 CHAR)          := '&ds_force';
    l_update_secret VARCHAR2(10 CHAR)       := '&ds_update_secret';
    l_user_exists   PLS_INTEGER;
    l_sql           text_type;              -- sql used in EXECUTE IMMEDIATE
BEGIN
    -- normalize inputs
    l_username := UPPER(l_username);
    l_profile  := UPPER(l_profile);
    l_force    :=UPPER(l_force);
    l_update_secret := UPPER(l_update_secret);
    -- Check if user exists
    SELECT COUNT(*) INTO l_user_exists FROM DBA_USERS WHERE USERNAME = l_username; -- Replace 'desired_username' with the username you want to check.

    IF l_user_exists > 0 THEN
        DBMS_OUTPUT.PUT_LINE('User '|| l_username || ' does exists.');
        -- Drop user if exists and force=true
        IF l_force = 'TRUE' THEN
            sys.dbms_output.put_line('Recreate user ' || l_username || ' as force is TRUE....');
            BEGIN
                -- drop user
                l_sql := 'DROP USER ' || l_username || ' CASCADE';
                EXECUTE IMMEDIATE l_sql;
                sys.dbms_output.put_line('User ' || l_username || ' dropped.');
                -- create user
                l_sql := 'CREATE USER ' || l_username ||
                    ' IDENTIFIED BY "' || l_passwd || '"' ||
                    ' PROFILE ' || l_profile;
                EXECUTE IMMEDIATE l_sql;
                sys.dbms_output.put_line('User ' || l_username || ' created with profile ' || l_profile);
            EXCEPTION
                WHEN user_connected THEN
                    sys.dbms_output.put_line('WARNING: FORCE drop failed because user is connected (ORA-01940). Falling back to ALTER USER.');
                    l_sql := 'ALTER USER ' || l_username ||
                        ' IDENTIFIED BY "' || l_passwd || '"' ||
                        ' PROFILE ' || l_profile;
                    EXECUTE IMMEDIATE l_sql;
                    sys.dbms_output.put_line('User ' || l_username || ' altered with profile ' || l_profile);
            END;
        ELSE
            IF l_update_secret = 'TRUE' THEN
                sys.dbms_output.put_line('User ' || l_username || ' already exists. Updating secret and profile.');
                l_sql := 'ALTER USER ' || l_username ||
                    ' IDENTIFIED BY "' || l_passwd || '"' ||
                    ' PROFILE ' || l_profile;
                EXECUTE IMMEDIATE l_sql;
            ELSE
                sys.dbms_output.put_line('User ' || l_username || ' already exists. Updating profile only.');
                sys.dbms_output.put_line('Use UPDATE_SECRET=TRUE to reset the secret or FORCE=TRUE to drop/recreate.');

                l_sql := 'ALTER USER ' || l_username || ' PROFILE ' || l_profile;
                EXECUTE IMMEDIATE l_sql;
            END IF;
        END IF;
    ELSE
        DBMS_OUTPUT.PUT_LINE('User '|| l_username || ' does not exist.');
        l_sql := 'CREATE USER ' || l_username ||
            ' IDENTIFIED BY "' || l_passwd || '"' ||
            ' PROFILE ' || l_profile;
        EXECUTE IMMEDIATE l_sql;
        sys.dbms_output.put_line('User ' || l_username || ' created with profile ' || l_profile);
    END IF;

    -- Apply grants
    l_sql := 'GRANT CONNECT, RESOURCE TO ' || l_username;
    EXECUTE IMMEDIATE l_sql;
    sys.dbms_output.put_line('Grants CONNECT, RESOURCE applied to ' || l_username);
EXCEPTION
    WHEN password_reuse THEN
        sys.dbms_output.put_line('WARNING: Secret reuse detected (ORA-28007). Continuing without secret change.');
        l_sql := 'ALTER USER ' || l_username || ' PROFILE ' || l_profile;
        EXECUTE IMMEDIATE l_sql;
        l_sql := 'GRANT CONNECT, RESOURCE TO ' || l_username;
        EXECUTE IMMEDIATE l_sql;
        sys.dbms_output.put_line('Grants CONNECT, RESOURCE applied to ' || l_username);
    WHEN OTHERS THEN
        RAISE;
END;
/

SPOOL OFF
-- EOF -------------------------------------------------------------------------