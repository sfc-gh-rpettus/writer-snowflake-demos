-- =============================================================================
-- 99_demo_reset.sql  —  Apex Athletics Content Supply Chain
-- Resets activation state between demo runs.
-- Preserves all base data — only clears Writer-generated content.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;

-- Clear activation staging (Reverse ETL target)
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES;

-- Clear Writer-generated briefs and assets
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS;
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS;

-- Verify clean state
SELECT
  'CAMPAIGN_AUDIENCES' AS tbl,
  COUNT(*) AS row_count,
  'Expected: 0' AS expected
FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
UNION ALL
SELECT 'CAMPAIGN_BRIEFS', COUNT(*), 'Expected: 0'
FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS
UNION ALL
SELECT 'CONTENT_ASSETS', COUNT(*), 'Expected: 0'
FROM WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS;
