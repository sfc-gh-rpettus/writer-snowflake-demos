-- =============================================================================
-- 14_grants.sql  —  Apex Athletics Content Supply Chain
-- Final grant sweep — ensures all objects in WRITER.MARKETING are
-- accessible to WRITER_MARKETING_ROLE.
-- Run AFTER all other scripts have completed.
-- This is a safety net; all grants should already exist inline in each script.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;

-- ---------------------------------------------------------------------------
-- Database + schema (idempotent)
-- ---------------------------------------------------------------------------
GRANT USAGE ON DATABASE WRITER_SNOW_DEMO           TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON SCHEMA   WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Warehouse (idempotent)
-- ---------------------------------------------------------------------------
GRANT USAGE, OPERATE ON WAREHOUSE WRITER_WH TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- All regular tables — bulk SELECT
-- ---------------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- Write-back tables — Writer needs INSERT too
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS    TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS     TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Dynamic Tables — bulk SELECT
-- ---------------------------------------------------------------------------
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Stored Procedures
-- ---------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.ACTIVATE_SEGMENT(NUMBER, VARCHAR, VARCHAR)
  TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(VARCHAR, VARIANT)
  TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(VARCHAR, VARIANT)
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Cortex Search Services
-- ---------------------------------------------------------------------------
GRANT USAGE ON CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY_SEARCH
  TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS_SEARCH
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Semantic View
-- ---------------------------------------------------------------------------
GRANT SELECT ON VIEW WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360_SV TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Cortex Agent
-- ---------------------------------------------------------------------------
GRANT USAGE ON AGENT WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGN_PLANNER
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- MCP Server
-- ---------------------------------------------------------------------------
GRANT USAGE ON MCP SERVER WRITER_SNOW_DEMO.MARKETING.MARKETING_MCP_SERVER
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Future-proof grants (auto-grant new objects)
-- ---------------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES         IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE VIEWS          IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
SHOW GRANTS TO ROLE WRITER_MARKETING_ROLE;
