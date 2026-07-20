-- =============================================================================
-- 08_cortex_search.sql  —  Apex Athletics Content Supply Chain
-- Creates: CAMPAIGN_LIBRARY_SEARCH, CAMPAIGN_BRIEFS_SEARCH
-- Note: Cortex Search services take 1-5 minutes to index after creation.
--       Do not run search queries immediately after this script.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_LIBRARY_SEARCH
-- Indexes the 100 historical campaigns so the Cortex Agent can search for
-- relevant past campaigns when generating recommendations.
-- Query example: "What past campaigns worked for at-risk customers?"
-- ---------------------------------------------------------------------------
-- Note: ON clause accepts a single column — concatenate searchable fields into SEARCH_CONTENT
CREATE OR REPLACE CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY_SEARCH
  ON SEARCH_CONTENT
  ATTRIBUTES CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE, CHANNEL, TARGET_SEGMENT,
             TONE, PERFORMANCE_TIER, OPEN_RATE, CLICK_RATE, CONVERSION_RATE
  WAREHOUSE = WRITER_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Search index for 100 historical Apex Athletics campaigns'
AS
  SELECT
    CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE, CHANNEL, TARGET_SEGMENT,
    TONE, PERFORMANCE_TIER, OPEN_RATE, CLICK_RATE, CONVERSION_RATE,
    COALESCE(SUBJECT_LINE, '') || ' ' ||
    COALESCE(BODY_PREVIEW, '') || ' ' ||
    COALESCE(CTA_TEXT, '') || ' ' ||
    COALESCE(TAGS, '') || ' ' ||
    COALESCE(TARGET_SEGMENT, '') AS SEARCH_CONTENT
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY;

GRANT USAGE ON CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY_SEARCH
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_BRIEFS_SEARCH
-- Indexes campaign briefs written back by Writer during demo.
-- Writer uses this to retrieve past briefs as structural context when
-- generating new ones (avoids duplication, maintains consistency).
-- This service starts empty and grows as Writer generates briefs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS_SEARCH
  ON SEARCH_CONTENT
  ATTRIBUTES BRIEF_ID, CAMPAIGN_ID, AUDIENCE_SEGMENT_ID, STATUS, CREATED_BY
  WAREHOUSE = WRITER_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Search index for campaign briefs — populated by Writer during demo'
AS
  SELECT
    BRIEF_ID, CAMPAIGN_ID, AUDIENCE_SEGMENT_ID, STATUS, CREATED_BY,
    COALESCE(PERSONA_NAME, '') || ' ' ||
    COALESCE(OBJECTIVE, '') || ' ' ||
    COALESCE(TARGET_AUDIENCE_DESCRIPTION, '') || ' ' ||
    COALESCE(TONE, '') || ' ' ||
    COALESCE(BRAND_VOICE_NOTES, '') AS SEARCH_CONTENT
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS;

GRANT USAGE ON CORTEX SEARCH SERVICE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS_SEARCH
  TO ROLE WRITER_MARKETING_ROLE;
