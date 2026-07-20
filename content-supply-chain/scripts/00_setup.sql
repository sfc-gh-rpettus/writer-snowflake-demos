-- =============================================================================
-- 00_setup.sql  —  Apex Athletics Content Supply Chain
-- Creates: WRITER_SNOW_DEMO database, WRITER_SNOW_DEMO.MARKETING schema,
--          WRITER_WH warehouse, WRITER_MARKETING_ROLE, and all base grants.
-- Run as SYSADMIN (or ACCOUNTADMIN).
-- PORTABILITY NOTE: Steps 1-2 must be run as ACCOUNTADMIN on a fresh account.
--   SYSADMIN does not have CREATE AGENT / CREATE MCP SERVER by default.
--   Uncomment the ACCOUNTADMIN block if needed.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Step 1 (ACCOUNTADMIN only) — grant schema-level CREATE privileges to SYSADMIN
-- Run this block first if SYSADMIN doesn't already have these privileges.
-- On demo490 these are pre-granted; on a fresh account they are not.
-- ---------------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
-- GRANT CREATE DYNAMIC TABLE         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
-- GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
-- GRANT CREATE SEMANTIC VIEW         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
-- GRANT CREATE AGENT                 ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
-- GRANT CREATE MCP SERVER            ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;

-- Step 2 — continue as SYSADMIN for all object creation
USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- Warehouse
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS WRITER_WH
  WITH WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 300
  AUTO_RESUME  = TRUE
  COMMENT = 'Dedicated warehouse for Apex Athletics Content Supply Chain demo';

-- ---------------------------------------------------------------------------
-- Database  (new — separate from existing WRITER database)
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS WRITER_SNOW_DEMO
  COMMENT = 'Apex Athletics Content Supply Chain demo account';

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS WRITER_SNOW_DEMO.MARKETING
  COMMENT = 'Apex Athletics Content Supply Chain demo — all objects live here';

USE WAREHOUSE WRITER_WH;

-- ---------------------------------------------------------------------------
-- Role
-- Owned by SYSADMIN (build role). Used by:
--   • SE running the demo in Snowsight
--   • Writer MCP client authenticating via WRITER_OAUTH integration
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS WRITER_MARKETING_ROLE
  COMMENT = 'Demo role for SE walkthroughs and Writer MCP Server connection';

-- Role hierarchy — WRITER_MARKETING_ROLE sits under SYSADMIN
GRANT ROLE WRITER_MARKETING_ROLE TO ROLE SYSADMIN;
-- IMPORTANT: Replace DEMO_USER below with your actual Snowflake username
GRANT ROLE WRITER_MARKETING_ROLE TO USER DEMO_USER;

-- ---------------------------------------------------------------------------
-- Warehouse access
-- ---------------------------------------------------------------------------
GRANT USAGE   ON WAREHOUSE WRITER_WH TO ROLE WRITER_MARKETING_ROLE;
GRANT OPERATE ON WAREHOUSE WRITER_WH TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Database + schema access
-- ---------------------------------------------------------------------------
GRANT USAGE ON DATABASE WRITER_SNOW_DEMO           TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON SCHEMA   WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- OAuth Security Integration — Writer MCP authentication
-- WRITER_OAUTH already exists in this account — skip this block.
-- For a fresh account, uncomment and run this BEFORE the rest of the script.
-- The OAuth client credentials (client ID / secret) are provided by Writer.
-- ---------------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
-- CREATE SECURITY INTEGRATION IF NOT EXISTS WRITER_OAUTH
--   TYPE = OAUTH
--   OAUTH_CLIENT = CUSTOM
--   OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
--   OAUTH_REDIRECT_URI = 'https://app.writer.com/mcp/oauth/callback'
--   OAUTH_ISSUE_REFRESH_TOKENS = TRUE
--   OAUTH_REFRESH_TOKEN_VALIDITY = 7776000
--   OAUTH_USE_SECONDARY_ROLES = IMPLICIT
--   BLOCKED_ROLES_LIST = ('ACCOUNTADMIN', 'ORGADMIN', 'SECURITYADMIN')
--   COMMENT = 'OAuth integration for Writer MCP client connection';
-- -- After creation, share the OAuth client ID with Writer:
-- -- SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WRITER_OAUTH');

-- Grant the demo role access to authenticate via this integration
-- (uncomment after WRITER_MARKETING_ROLE is created above)
-- GRANT USAGE ON INTEGRATION WRITER_OAUTH TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Future-proof grants (auto-grant new tables/views created after this point)
-- ---------------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES         IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE VIEWS          IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

