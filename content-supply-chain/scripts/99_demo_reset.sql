-- =============================================================================
-- 99_demo_reset.sql  —  Apex Athletics Content Supply Chain
-- Resets activation state between demo runs.
-- Preserves all base data — only clears Writer-generated content
-- and performance events seeded by ACTIVATE_SEGMENT.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;

-- Clear activation staging (Reverse ETL target)
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES;

-- Clear Writer-generated briefs and assets
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS;
TRUNCATE TABLE WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS;

-- Clear synthetic performance events seeded by ACTIVATE_SEGMENT
-- (these have EVENT_IDs starting with 'S' — the seeded flywheel data)
DELETE FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
WHERE EVENT_ID LIKE 'S%';

-- Verify clean state
SELECT
  'CAMPAIGN_AUDIENCES'   AS tbl, COUNT(*) AS row_count, 'Expected: 0' AS expected
FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
UNION ALL SELECT 'CAMPAIGN_BRIEFS',  COUNT(*), 'Expected: 0'
FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS
UNION ALL SELECT 'CONTENT_ASSETS',   COUNT(*), 'Expected: 0'
FROM WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS
UNION ALL SELECT 'CAMPAIGN_EVENTS (seeded)', COUNT(*), 'Expected: 0'
FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS WHERE EVENT_ID LIKE 'S%';
