-- =============================================================================
-- 12_perf_gold.sql  —  Apex Athletics Content Supply Chain
-- Creates: CAMPAIGN_PERFORMANCE_GOLD Dynamic Table
-- Joins CAMPAIGN_EVENTS + CAMPAIGN_LIBRARY + MICRO_SEGMENTS for CoWork analytics.
-- Also pre-loads PAID_MEDIA_PERFORMANCE with synthetic ad platform data
-- (used as a source table for this DT).
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- PAID_MEDIA_PERFORMANCE — synthetic ad platform performance data
-- Pre-loaded (no live Snowpipe wiring — synthetic data is sufficient for demo)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.PAID_MEDIA_PERFORMANCE (
  RECORD_ID      VARCHAR(20)   NOT NULL,
  CAMPAIGN_ID    VARCHAR(15),
  ASSET_ID       VARCHAR(30),
  PLATFORM       VARCHAR(20),   -- meta/google/tiktok/linkedin/pinterest
  AD_SET_NAME    VARCHAR(100),
  DATE           DATE          NOT NULL,
  IMPRESSIONS    NUMBER(12,0),
  CLICKS         NUMBER(10,0),
  SPEND          NUMBER(10,2),
  CONVERSIONS    NUMBER(8,0),
  REVENUE        NUMBER(12,2),
  CPM            NUMBER(8,2),
  CPC            NUMBER(8,2),
  ROAS           NUMBER(8,4),
  CAC            NUMBER(8,2)
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.PAID_MEDIA_PERFORMANCE
WITH
  campaigns AS (
    SELECT c.value::VARCHAR AS cid, c.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["CMP-2025-001","CMP-2025-006","CMP-2025-016","CMP-2025-026","CMP-2025-061","CMP-2025-081"]'))) c
  ),
  platforms AS (
    SELECT p.value::VARCHAR AS plt, p.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["meta","google","tiktok","linkedin","pinterest"]'))) p
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 18000)))
SELECT
  'PMP-' || LPAD(g.n + 1, 7, '0')                               AS RECORD_ID,
  camp.cid                                                        AS CAMPAIGN_ID,
  NULL                                                            AS ASSET_ID,
  plt.plt                                                         AS PLATFORM,
  camp.cid || '_' || plt.plt || '_adset_' || MOD(g.n, 5)         AS AD_SET_NAME,
  DATEADD(day, -MOD(g.n, 180), CURRENT_DATE())                   AS DATE,
  UNIFORM(1000, 50000, RANDOM())                                  AS IMPRESSIONS,
  UNIFORM(10, 2000, RANDOM())                                     AS CLICKS,
  ROUND(UNIFORM(5.0, 500.0, RANDOM()), 2)                        AS SPEND,
  UNIFORM(0, 50, RANDOM())                                        AS CONVERSIONS,
  ROUND(UNIFORM(0, 2000.0, RANDOM()), 2)                         AS REVENUE,
  ROUND(UNIFORM(2.0, 25.0, RANDOM()), 2)                         AS CPM,
  ROUND(UNIFORM(0.25, 8.0, RANDOM()), 2)                         AS CPC,
  ROUND(UNIFORM(0.5, 8.0, RANDOM()), 4)                          AS ROAS,
  ROUND(UNIFORM(5.0, 150.0, RANDOM()), 2)                        AS CAC
FROM gen g
JOIN campaigns camp ON camp.idx = MOD(g.n, 6)
JOIN platforms plt   ON plt.idx  = MOD(g.n, 5);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.PAID_MEDIA_PERFORMANCE TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_PERFORMANCE_GOLD — Dynamic Table
-- Aggregates CAMPAIGN_EVENTS + PAID_MEDIA_PERFORMANCE + CAMPAIGN_LIBRARY
-- Used by the Cortex Agent in CoWork mode for campaign analytics queries.
-- TARGET_LAG = '1 hour', FULL refresh
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_PERFORMANCE_GOLD
  -- Demo env: 1 day — sources are static synthetic data.
  -- In production set to '1 hour' once Snowpipe is wired to return Braze engagement events.
  TARGET_LAG = '1 day'
  WAREHOUSE  = WRITER_WH
  REFRESH_MODE = FULL
  COMMENT = 'Campaign performance analytics — joins events + paid media + library for CoWork'
AS
WITH
  -- Email/push/SMS campaign metrics from CAMPAIGN_EVENTS
  owned_metrics AS (
    SELECT
      ce.CAMPAIGN_ID,
      cl.CAMPAIGN_NAME,
      cl.CAMPAIGN_TYPE,
      ce.CHANNEL,
      DATE_TRUNC('week', ce.EVENT_TIMESTAMP)::DATE     AS PERIOD,
      COUNT_IF(ce.EVENT_TYPE = 'send')                  AS SENDS,
      COUNT_IF(ce.EVENT_TYPE = 'open')                  AS OPENS,
      COUNT_IF(ce.EVENT_TYPE = 'click')                 AS CLICKS,
      COUNT_IF(ce.EVENT_TYPE = 'convert')               AS CONVERSIONS,
      SUM(COALESCE(ce.REVENUE, 0))                      AS OWNED_REVENUE,
      COUNT_IF(ce.EVENT_TYPE = 'bounce')                AS BOUNCES,
      COUNT_IF(ce.EVENT_TYPE = 'unsubscribe')           AS UNSUBSCRIBES
    FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS ce
    LEFT JOIN WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY cl ON cl.CAMPAIGN_ID = ce.CAMPAIGN_ID
    GROUP BY ce.CAMPAIGN_ID, cl.CAMPAIGN_NAME, cl.CAMPAIGN_TYPE, ce.CHANNEL,
             DATE_TRUNC('week', ce.EVENT_TIMESTAMP)::DATE
  ),
  -- Paid media metrics from PAID_MEDIA_PERFORMANCE
  paid_metrics AS (
    SELECT
      CAMPAIGN_ID,
      PLATFORM,
      DATE_TRUNC('week', DATE)::DATE   AS PERIOD,
      SUM(IMPRESSIONS)                  AS IMPRESSIONS,
      SUM(CLICKS)                       AS PAID_CLICKS,
      SUM(SPEND)                        AS SPEND,
      SUM(CONVERSIONS)                  AS PAID_CONVERSIONS,
      SUM(REVENUE)                      AS PAID_REVENUE,
      AVG(ROAS)                         AS AVG_ROAS,
      AVG(CAC)                          AS AVG_CAC
    FROM WRITER_SNOW_DEMO.MARKETING.PAID_MEDIA_PERFORMANCE
    GROUP BY CAMPAIGN_ID, PLATFORM, DATE_TRUNC('week', DATE)::DATE
  ),
  -- Join and compute final metrics
  combined AS (
    SELECT
      COALESCE(om.CAMPAIGN_ID, pm.CAMPAIGN_ID)     AS CAMPAIGN_ID,
      COALESCE(om.CAMPAIGN_NAME, om.CAMPAIGN_ID)   AS CAMPAIGN_NAME,
      om.CAMPAIGN_TYPE,
      COALESCE(om.CHANNEL, pm.PLATFORM)            AS CHANNEL,
      COALESCE(om.PERIOD, pm.PERIOD)               AS PERIOD,
      COALESCE(om.SENDS, 0)                        AS SENDS,
      COALESCE(om.OPENS, 0)                        AS OPENS,
      COALESCE(om.CLICKS, 0)                       AS CLICKS,
      COALESCE(om.CONVERSIONS, 0) +
        COALESCE(pm.PAID_CONVERSIONS, 0)           AS CONVERSIONS,
      COALESCE(om.OWNED_REVENUE, 0) +
        COALESCE(pm.PAID_REVENUE, 0)               AS TOTAL_REVENUE,
      COALESCE(pm.SPEND, 0)                        AS PAID_SPEND,
      COALESCE(pm.IMPRESSIONS, 0)                  AS IMPRESSIONS,
      COALESCE(pm.AVG_ROAS, 0)                     AS ROAS,
      COALESCE(pm.AVG_CAC, 0)                      AS CAC
    FROM owned_metrics om
    FULL OUTER JOIN paid_metrics pm
      ON pm.CAMPAIGN_ID = om.CAMPAIGN_ID
      AND pm.PERIOD = om.PERIOD
  )
SELECT
  CAMPAIGN_ID,
  CAMPAIGN_NAME,
  CAMPAIGN_TYPE,
  CHANNEL,
  PERIOD,
  SENDS,
  OPENS,
  CLICKS,
  CONVERSIONS,
  TOTAL_REVENUE,
  PAID_SPEND,
  IMPRESSIONS,
  ROAS,
  CAC,
  -- Derived rates
  CASE WHEN SENDS > 0 THEN ROUND(OPENS::FLOAT / SENDS, 4) ELSE 0 END    AS EMAIL_OPEN_RATE,
  CASE WHEN OPENS > 0 THEN ROUND(CLICKS::FLOAT / OPENS, 4) ELSE 0 END   AS CTR,
  CASE WHEN SENDS > 0 THEN ROUND(CONVERSIONS::FLOAT / SENDS, 4) ELSE 0 END AS CVR
FROM combined
WHERE PERIOD IS NOT NULL;

GRANT SELECT ON DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_PERFORMANCE_GOLD
  TO ROLE WRITER_MARKETING_ROLE;
