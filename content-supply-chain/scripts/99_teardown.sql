-- =============================================================================
-- 99_teardown.sql  —  Apex Athletics Content Supply Chain
-- NUCLEAR OPTION — drops the entire WRITER_SNOW_DEMO database and demo role.
-- Only run this when decommissioning the demo entirely.
-- For between-demo cleanup, use 99_demo_reset.sql instead.
--
-- Run as ACCOUNTADMIN (SYSADMIN does not have DROP DATABASE privilege).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WRITER_WH;

-- Drops the database and cascades to ALL objects inside it:
-- schema, tables, dynamic tables, procedures, cortex search services,
-- semantic view, cortex agent, and MCP server.
DROP DATABASE IF EXISTS WRITER_SNOW_DEMO;

-- Drop the demo role separately (lives outside the database)
DROP ROLE IF EXISTS WRITER_MARKETING_ROLE;

-- Verify
SHOW DATABASES LIKE 'WRITER_SNOW_DEMO';  -- should be empty
SHOW ROLES LIKE 'WRITER_MARKETING%';     -- should be empty
