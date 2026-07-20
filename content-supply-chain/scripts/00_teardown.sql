-- =============================================================================
-- 00_teardown.sql  —  Apex Athletics Content Supply Chain
-- Removes all demo objects created under WRITER_SNOW_DEMO.MARKETING.
-- Also drops the WRITER_SNOW_DEMO database entirely (it was created solely
-- for this demo — no other schemas exist in it).
-- Does NOT touch WRITER database or other pre-existing objects.
-- Safe to run multiple times (IF EXISTS everywhere).
-- Run as SYSADMIN or ACCOUNTADMIN.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;

-- ---------------------------------------------------------------------------
-- Drop AI objects first (dependencies)
-- ---------------------------------------------------------------------------
DROP MCP SERVER            IF EXISTS WRITER_SNOW_DEMO.MARKETING.MARKETING_MCP_SERVER;
DROP AGENT                 IF EXISTS WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGN_PLANNER;
DROP CORTEX SEARCH SERVICE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY_SEARCH;
DROP CORTEX SEARCH SERVICE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS_SEARCH;

-- ---------------------------------------------------------------------------
-- Drop Semantic View
-- ---------------------------------------------------------------------------
DROP SEMANTIC VIEW         IF EXISTS WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360_SV;

-- ---------------------------------------------------------------------------
-- Drop Stored Procedures
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS WRITER_SNOW_DEMO.MARKETING.ACTIVATE_SEGMENT(NUMBER, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(VARCHAR, VARIANT);
DROP PROCEDURE IF EXISTS WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(VARCHAR, VARIANT);

-- ---------------------------------------------------------------------------
-- Drop Dynamic Tables
-- ---------------------------------------------------------------------------
DROP DYNAMIC TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_PERFORMANCE_GOLD;
DROP DYNAMIC TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS;
DROP DYNAMIC TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360;

-- ---------------------------------------------------------------------------
-- Drop all regular tables
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CUSTOMERS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.PAID_MEDIA_PERFORMANCE;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.PRODUCT_SENTIMENT_SCORES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.GEO_SEARCH_QUERIES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.BRAND_VOICE_GUIDELINES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.CHANNEL_TEMPLATES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.AUDIENCE_SEGMENTS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGNS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.PRODUCT_CATEGORIES;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.LOYALTY_TIERS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.PROMOTIONS;
DROP TABLE IF EXISTS WRITER_SNOW_DEMO.MARKETING.STORES;

-- ---------------------------------------------------------------------------
-- Drop the database (and schema within it) — safe since WRITER_SNOW_DEMO
-- was created exclusively for this demo
-- ---------------------------------------------------------------------------
DROP DATABASE IF EXISTS WRITER_SNOW_DEMO;

-- ---------------------------------------------------------------------------
-- Drop the demo role
-- ---------------------------------------------------------------------------
DROP ROLE IF EXISTS WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- Verify teardown
-- ---------------------------------------------------------------------------
SHOW DATABASES LIKE 'WRITER_SNOW_DEMO';   -- should be empty
SHOW ROLES LIKE 'WRITER_MARKETING%';      -- should be empty
