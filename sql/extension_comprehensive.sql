-- -----------------------------------------------------------------------------
-- OraDBA Extension - Oracle Database Infrastructure and Security
-- -----------------------------------------------------------------------------
-- Name......: extension_comprehensive.sql
-- Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
-- Editor....: Stefan Oehrli
-- Date......: 2026.01.07
-- Revision..: 0.2.0
-- Usage.....: @extension_comprehensive.sql
--             Or via SQL*Plus with automatic spool:
--             sqlplus / as sysdba @extension_comprehensive.sql
-- Purpose...: Comprehensive SQL script example demonstrating advanced features
-- Notes.....: This example shows:
--             - Automatic log directory detection from ORADBA_LOG
--             - Dynamic spool file naming with timestamp and SID
--             - Multiple related queries with section headers
--             - Proper error handling with WHENEVER
--             - Environment variable integration
--             - Production-ready logging patterns
-- Reference.: https://github.com/oehrlis/oradba_extension
-- License...: Apache License Version 2.0, January 2004 as shown
--             at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

-- =============================================================================
-- Environment Setup and Spool Configuration
-- =============================================================================

-- Enable server output and configure formatting
SET SERVEROUTPUT ON
SET LINESIZE 200 PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK ON

-- Configure spool directory and filename components
-- Set LOGDIR via SQL*Plus -DEFINE LOGDIR=/path or accept default '.'
-- HOST temp-file pattern removed: /tmp/oradba_logdir_${USER}.sql was world-readable
-- with a predictable path (ORA-009 hardening).
DEFINE LOGDIR = '.'
DEFINE TIMESTAMP = 'UNKNOWN'
DEFINE DBSID = 'UNKNOWN'

-- Get timestamp and database SID for filename
COLUMN logts NEW_VALUE TIMESTAMP NOPRINT
COLUMN logsid NEW_VALUE DBSID NOPRINT
SELECT TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') AS logts,
       LOWER(SYS_CONTEXT('USERENV', 'INSTANCE_NAME')) AS logsid
FROM DUAL;

-- Start spooling to log file
SPOOL &LOGDIR./extension_comprehensive_&DBSID._&TIMESTAMP..log

PROMPT
PROMPT ================================================================================
PROMPT = OraDBA Extension - Comprehensive Database Report
PROMPT = Script: extension_comprehensive.sql
PROMPT = Date: &TIMESTAMP
PROMPT = Database: &DBSID
PROMPT ================================================================================
PROMPT

-- =============================================================================
-- Section 1: Database Configuration
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Database Configuration and Settings
PROMPT ================================================================================
PROMPT

-- Database basic information
SELECT d.name           AS database_name,
       d.dbid           AS database_id,
       d.db_unique_name AS unique_name,
       d.platform_name  AS platform,
       d.open_mode      AS open_mode,
       d.log_mode       AS archive_mode,
       d.force_logging  AS force_logging,
       d.created        AS created_date
FROM   v$database d;

PROMPT
PROMPT Database Version and Edition:
PROMPT

SELECT i.instance_name  AS instance,
       i.version        AS version,
       i.edition        AS edition,
       i.host_name      AS host,
       i.status         AS status,
       i.startup_time   AS startup_time,
       i.database_status AS db_status
FROM   v$instance i;

-- =============================================================================
-- Section 2: Tablespace Usage
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Tablespace Usage Summary
PROMPT ================================================================================
PROMPT

COLUMN tablespace_name FORMAT A30
COLUMN total_mb FORMAT 999,999,999
COLUMN used_mb FORMAT 999,999,999
COLUMN free_mb FORMAT 999,999,999
COLUMN pct_used FORMAT 999.99

SELECT df.tablespace_name,
       ROUND(df.total_mb, 2) AS total_mb,
       ROUND(df.total_mb - NVL(fs.free_mb, 0), 2) AS used_mb,
       ROUND(NVL(fs.free_mb, 0), 2) AS free_mb,
       ROUND((df.total_mb - NVL(fs.free_mb, 0)) / df.total_mb * 100, 2) AS pct_used,
       df.status
FROM   (SELECT tablespace_name,
               SUM(bytes) / 1024 / 1024 AS total_mb,
               status
        FROM   dba_data_files
        GROUP BY tablespace_name, status) df
LEFT JOIN
       (SELECT tablespace_name,
               SUM(bytes) / 1024 / 1024 AS free_mb
        FROM   dba_free_space
        GROUP BY tablespace_name) fs
ON     df.tablespace_name = fs.tablespace_name
ORDER BY pct_used DESC;

-- =============================================================================
-- Section 3: Session Information
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Current Session and Connection Details
PROMPT ================================================================================
PROMPT

SELECT SYS_CONTEXT('USERENV', 'SESSION_USER')       AS session_user,
       SYS_CONTEXT('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_id,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')     AS current_schema,
       SYS_CONTEXT('USERENV', 'INSTANCE_NAME')      AS instance_name,
       SYS_CONTEXT('USERENV', 'SERVER_HOST')        AS server_host,
       SYS_CONTEXT('USERENV', 'IP_ADDRESS')         AS client_ip,
       SYS_CONTEXT('USERENV', 'SESSIONID')          AS session_id,
       SYS_CONTEXT('USERENV', 'SID')                AS oracle_sid
FROM   dual;

-- =============================================================================
-- Section 4: Top Objects by Size
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Top 10 Database Objects by Size
PROMPT ================================================================================
PROMPT

COLUMN owner FORMAT A20
COLUMN segment_name FORMAT A40
COLUMN segment_type FORMAT A18
COLUMN size_mb FORMAT 999,999,999

SELECT *
FROM   (SELECT owner,
               segment_name,
               segment_type,
               ROUND(SUM(bytes) / 1024 / 1024, 2) AS size_mb
        FROM   dba_segments
        WHERE  owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'XDB', 'CTXSYS', 'MDSYS', 'ORDSYS')
        GROUP BY owner, segment_name, segment_type
        ORDER BY SUM(bytes) DESC)
WHERE  ROWNUM <= 10;

-- =============================================================================
-- Section 5: Recent Database Activity
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Top SQL Statements by Executions (Last 24 Hours)
PROMPT ================================================================================
PROMPT

COLUMN sql_text FORMAT A60 TRUNCATE
COLUMN executions FORMAT 999,999,999
COLUMN elapsed_sec FORMAT 999,999.99

SELECT *
FROM   (SELECT SUBSTR(sql_text, 1, 60) AS sql_text,
               executions,
               ROUND(elapsed_time / 1000000, 2) AS elapsed_sec,
               ROUND(cpu_time / 1000000, 2) AS cpu_sec,
               disk_reads,
               buffer_gets
        FROM   v$sql
        WHERE  last_active_time > SYSDATE - 1
          AND  executions > 0
          AND  parsing_schema_name NOT IN ('SYS', 'SYSTEM')
        ORDER BY executions DESC)
WHERE  ROWNUM <= 10;

-- =============================================================================
-- Script Completion
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT = Report Generation Completed
PROMPT = Output file: &LOGDIR./extension_comprehensive_&DBSID._&TIMESTAMP..log
PROMPT ================================================================================
PROMPT

-- Stop spooling
SPOOL OFF

-- Reset SQL*Plus settings
SET VERIFY ON
SET FEEDBACK ON

-- Script completion message
PROMPT Report generated successfully. Check the log file for details.
