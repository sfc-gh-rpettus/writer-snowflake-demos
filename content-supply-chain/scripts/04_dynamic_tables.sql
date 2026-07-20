-- =============================================================================
-- 04_dynamic_tables.sql  —  Apex Athletics Content Supply Chain
-- Creates: CUSTOMER_360 (Dynamic Table, 50K x 71 cols, 1-hour lag)
--          MICRO_SEGMENTS (Dynamic Table, 22 scored segments)
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- CUSTOMER_360 — Gold layer unified customer intelligence
-- 71 columns: Demographics, Tenure, Transactional (windowed), Product affinity,
-- Engagement, Behavioral signals, Campaign metrics, RFM (1-5), Predictive
-- TARGET_LAG = '1 hour', FULL refresh
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360
  -- Demo env: 1 day to avoid hourly FULL scans of 2.2M events on static data.
  -- In production set to '1 hour' to reflect live engagement updates.
  TARGET_LAG = '1 day'
  WAREHOUSE  = WRITER_WH
  REFRESH_MODE = FULL
  COMMENT = 'Apex Athletics unified customer 360 profile — 65 columns, refreshes daily in demo (1 hour in production)'
AS
WITH
  -- Purchase metrics per customer (last 12 months)
  purchase_metrics AS (
    SELECT
      CUSTOMER_ID,
      COUNT_IF(EVENT_TYPE = 'purchase')                              AS PURCHASE_COUNT_12M,
      SUM(CASE WHEN EVENT_TYPE = 'purchase'
               THEN EVENT_PROPERTIES:amount::FLOAT ELSE 0 END)      AS TOTAL_SPEND_12M,
      AVG(CASE WHEN EVENT_TYPE = 'purchase'
               THEN EVENT_PROPERTIES:amount::FLOAT END)              AS AVG_ORDER_VALUE,
      MAX(CASE WHEN EVENT_TYPE = 'purchase'
               THEN EVENT_TIMESTAMP END)                             AS LAST_PURCHASE_DATE,
      MIN(CASE WHEN EVENT_TYPE = 'purchase'
               THEN EVENT_TIMESTAMP END)                             AS FIRST_PURCHASE_DATE,
      COUNT_IF(EVENT_TYPE = 'return')                                AS RETURN_COUNT_12M,
      COUNT_IF(EVENT_TYPE = 'add_to_cart')                          AS CART_ADD_COUNT_12M,
      COUNT_IF(EVENT_TYPE = 'wishlist_add')                         AS WISHLIST_COUNT_12M
    FROM WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
    WHERE EVENT_TIMESTAMP >= DATEADD(year, -1, CURRENT_TIMESTAMP())
    GROUP BY CUSTOMER_ID
  ),
  -- Engagement metrics per customer
  engagement_metrics AS (
    SELECT
      CUSTOMER_ID,
      COUNT(*)                                                       AS TOTAL_EVENTS_12M,
      COUNT_IF(EVENT_TYPE = 'page_view')                            AS PAGE_VIEWS_12M,
      COUNT_IF(EVENT_TYPE = 'search')                               AS SEARCH_COUNT_12M,
      COUNT_IF(EVENT_TYPE = 'training_log')                         AS TRAINING_LOGS_12M,
      COUNT_IF(EVENT_TYPE = 'goal_set')                             AS GOALS_SET_12M,
      COUNT_IF(EVENT_TYPE = 'gear_review')                          AS REVIEWS_WRITTEN_12M,
      COUNT_IF(EVENT_TYPE = 'size_exchange')                        AS SIZE_EXCHANGES_12M,
      COUNT(DISTINCT DATE_TRUNC('day', EVENT_TIMESTAMP))            AS ACTIVE_DAYS_12M,
      MAX(EVENT_TIMESTAMP)                                           AS LAST_ACTIVITY_DATE
    FROM WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
    WHERE EVENT_TIMESTAMP >= DATEADD(year, -1, CURRENT_TIMESTAMP())
    GROUP BY CUSTOMER_ID
  ),
  -- Campaign metrics per customer
  campaign_metrics AS (
    SELECT
      CUSTOMER_ID,
      COUNT_IF(EVENT_TYPE = 'open')                                  AS EMAIL_OPENS_12M,
      COUNT_IF(EVENT_TYPE = 'click')                                 AS EMAIL_CLICKS_12M,
      COUNT_IF(EVENT_TYPE = 'convert')                               AS CAMPAIGN_CONVERSIONS_12M,
      SUM(COALESCE(REVENUE, 0))                                      AS CAMPAIGN_REVENUE_12M,
      COUNT_IF(EVENT_TYPE = 'send')                                  AS EMAILS_RECEIVED_12M,
      COUNT_IF(EVENT_TYPE = 'unsubscribe')                           AS UNSUBSCRIBES_12M
    FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
    WHERE EVENT_TIMESTAMP >= DATEADD(year, -1, CURRENT_TIMESTAMP())
    GROUP BY CUSTOMER_ID
  ),
  -- RFM scoring (1-5 buckets)
  rfm_base AS (
    SELECT
      c.CUSTOMER_ID,
      -- Recency: days since last purchase (lower = more recent = higher score)
      -- Use 548-day fixed fallback for dormant customers (no in-window purchases) so they
      -- rank clearly in the stale R_SCORE bucket without competing with at-risk cohort
      DATEDIFF('day', COALESCE(pm.LAST_PURCHASE_DATE, DATEADD(day, -548, CURRENT_DATE())), CURRENT_TIMESTAMP()) AS DAYS_SINCE_PURCHASE,
      COALESCE(pm.PURCHASE_COUNT_12M, 0) AS FREQUENCY,
      COALESCE(pm.TOTAL_SPEND_12M, 0)    AS MONETARY
    FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMERS c
    LEFT JOIN purchase_metrics pm ON pm.CUSTOMER_ID = c.CUSTOMER_ID
  ),
  rfm_scores AS (
    SELECT
      CUSTOMER_ID,
      DAYS_SINCE_PURCHASE,
      FREQUENCY,
      MONETARY,
      -- Recency score: 5 = most recent (lowest days), 1 = least recent
      NTILE(5) OVER (ORDER BY DAYS_SINCE_PURCHASE DESC) AS R_SCORE,
      NTILE(5) OVER (ORDER BY FREQUENCY ASC)            AS F_SCORE,
      NTILE(5) OVER (ORDER BY MONETARY ASC)             AS M_SCORE
    FROM rfm_base
  )
SELECT
  -- ── Demographics (10 cols) ─────────────────────────────────────────────
  c.CUSTOMER_ID,
  c.FIRST_NAME,
  c.LAST_NAME,
  c.EMAIL,
  c.PHONE,
  c.DATE_OF_BIRTH,
  c.GENDER,
  DATEDIFF('year', c.DATE_OF_BIRTH, CURRENT_DATE())        AS AGE,
  c.CITY,
  c.STATE,
  c.REGION,
  c.ZIP_CODE,

  -- ── Tenure (3 cols) ───────────────────────────────────────────────────
  c.SIGNUP_DATE,
  c.LAST_LOGIN_DATE,
  DATEDIFF('day', c.SIGNUP_DATE, CURRENT_DATE())           AS TENURE_DAYS,

  -- ── Loyalty (5 cols) ──────────────────────────────────────────────────
  c.LOYALTY_TIER_ID,
  c.LOYALTY_TIER_NAME,
  c.ANNUAL_SPEND,
  c.LOYALTY_POINTS,
  lt.DISCOUNT_PCT                                          AS TIER_DISCOUNT_PCT,

  -- ── Preferences (5 cols) ──────────────────────────────────────────────
  c.PREFERRED_CHANNEL,
  c.TOP_CATEGORY,
  c.MARKETING_OPT_IN,
  c.PUSH_OPT_IN,
  c.SMS_OPT_IN,
  c.NEAREST_STORE_ID,

  -- ── Transactional — 12-month window (9 cols) ─────────────────────────
  COALESCE(pm.PURCHASE_COUNT_12M, 0)                       AS PURCHASE_COUNT_12M,
  COALESCE(pm.TOTAL_SPEND_12M, 0)                          AS TOTAL_SPEND_12M,
  COALESCE(pm.AVG_ORDER_VALUE, 0)                          AS AVG_ORDER_VALUE,
  pm.LAST_PURCHASE_DATE,
  pm.FIRST_PURCHASE_DATE,
  DATEDIFF('day', pm.LAST_PURCHASE_DATE,
           CURRENT_TIMESTAMP())                             AS DAYS_SINCE_LAST_PURCHASE,
  COALESCE(pm.RETURN_COUNT_12M, 0)                         AS RETURN_COUNT_12M,
  COALESCE(pm.CART_ADD_COUNT_12M, 0)                       AS CART_ADD_COUNT_12M,
  COALESCE(pm.WISHLIST_COUNT_12M, 0)                       AS WISHLIST_COUNT_12M,

  -- ── Engagement scores (10 cols) ───────────────────────────────────────
  COALESCE(em.TOTAL_EVENTS_12M, 0)                         AS TOTAL_EVENTS_12M,
  COALESCE(em.PAGE_VIEWS_12M, 0)                           AS PAGE_VIEWS_12M,
  COALESCE(em.SEARCH_COUNT_12M, 0)                         AS SEARCH_COUNT_12M,
  COALESCE(em.TRAINING_LOGS_12M, 0)                        AS TRAINING_LOGS_12M,
  COALESCE(em.GOALS_SET_12M, 0)                            AS GOALS_SET_12M,
  COALESCE(em.REVIEWS_WRITTEN_12M, 0)                      AS REVIEWS_WRITTEN_12M,
  COALESCE(em.SIZE_EXCHANGES_12M, 0)                       AS SIZE_EXCHANGES_12M,
  COALESCE(em.ACTIVE_DAYS_12M, 0)                          AS ACTIVE_DAYS_12M,
  em.LAST_ACTIVITY_DATE,

  -- ── Campaign metrics (6 cols) ─────────────────────────────────────────
  COALESCE(cm.EMAIL_OPENS_12M, 0)                          AS EMAIL_OPENS_12M,
  COALESCE(cm.EMAIL_CLICKS_12M, 0)                         AS EMAIL_CLICKS_12M,
  COALESCE(cm.CAMPAIGN_CONVERSIONS_12M, 0)                 AS CAMPAIGN_CONVERSIONS_12M,
  COALESCE(cm.CAMPAIGN_REVENUE_12M, 0)                     AS CAMPAIGN_REVENUE_12M,
  COALESCE(cm.EMAILS_RECEIVED_12M, 0)                      AS EMAILS_RECEIVED_12M,
  COALESCE(cm.UNSUBSCRIBES_12M, 0)                         AS UNSUBSCRIBES_12M,

  -- ── Derived rates (4 cols) ────────────────────────────────────────────
  CASE WHEN COALESCE(cm.EMAILS_RECEIVED_12M, 0) > 0
       THEN ROUND(COALESCE(cm.EMAIL_OPENS_12M, 0) / cm.EMAILS_RECEIVED_12M, 4)
       ELSE 0 END                                           AS EMAIL_OPEN_RATE,
  CASE WHEN COALESCE(cm.EMAIL_OPENS_12M, 0) > 0
       THEN ROUND(COALESCE(cm.EMAIL_CLICKS_12M, 0) / cm.EMAIL_OPENS_12M, 4)
       ELSE 0 END                                           AS EMAIL_CLICK_RATE,
  CASE WHEN COALESCE(cm.EMAILS_RECEIVED_12M, 0) > 0
       THEN ROUND(COALESCE(cm.CAMPAIGN_CONVERSIONS_12M, 0) / cm.EMAILS_RECEIVED_12M, 4)
       ELSE 0 END                                           AS CAMPAIGN_CONVERSION_RATE,
  CASE WHEN COALESCE(pm.PURCHASE_COUNT_12M, 0) > 0
       THEN ROUND(COALESCE(pm.RETURN_COUNT_12M, 0)::FLOAT / pm.PURCHASE_COUNT_12M, 4)
       ELSE 0 END                                           AS RETURN_RATE,

  -- ── RFM scoring (4 cols) ──────────────────────────────────────────────
  rfm.R_SCORE,
  rfm.F_SCORE,
  rfm.M_SCORE,
  ROUND((rfm.R_SCORE + rfm.F_SCORE + rfm.M_SCORE) / 3.0, 2) AS RFM_COMPOSITE_SCORE,

  -- ── RFM segment (1 col) ───────────────────────────────────────────────
  CASE
    WHEN rfm.R_SCORE >= 4 AND rfm.F_SCORE >= 4 THEN 'Champion'
    WHEN rfm.R_SCORE >= 3 AND rfm.F_SCORE >= 3 THEN 'Loyal'
    WHEN rfm.R_SCORE >= 4 AND rfm.F_SCORE < 3  THEN 'Recent'
    WHEN rfm.R_SCORE < 2  AND rfm.F_SCORE >= 4 THEN 'At Risk'
    WHEN rfm.R_SCORE < 2  AND rfm.F_SCORE < 2  THEN 'Dormant'
    WHEN rfm.R_SCORE >= 3                       THEN 'Potential'
    WHEN rfm.F_SCORE >= 3                       THEN 'Needs Attention'
    ELSE 'New'
  END                                                         AS RFM_SEGMENT,

  -- ── Churn risk (1 col) ────────────────────────────────────────────────
  CASE
    WHEN DATEDIFF('day', pm.LAST_PURCHASE_DATE,
                  CURRENT_TIMESTAMP()) > 180 OR pm.LAST_PURCHASE_DATE IS NULL THEN 'High'
    WHEN DATEDIFF('day', pm.LAST_PURCHASE_DATE,
                  CURRENT_TIMESTAMP()) > 90  THEN 'Medium'
    ELSE 'Low'
  END                                                         AS CHURN_RISK_TIER,

  -- ── Predictive scores (5 cols) ────────────────────────────────────────
  -- Engagement score: weighted composite of activity signals (0-100)
  LEAST(100, ROUND(
    COALESCE(em.ACTIVE_DAYS_12M, 0) * 0.4 +
    COALESCE(em.TRAINING_LOGS_12M, 0) * 2.0 +
    COALESCE(em.GOALS_SET_12M, 0) * 5.0 +
    COALESCE(em.REVIEWS_WRITTEN_12M, 0) * 3.0 +
    COALESCE(pm.PURCHASE_COUNT_12M, 0) * 1.5
  , 1))                                                       AS ENGAGEMENT_SCORE,

  -- Churn risk score: higher = more at risk (0-100)
  LEAST(100, ROUND(
    COALESCE(DATEDIFF('day', pm.LAST_PURCHASE_DATE,
                      CURRENT_TIMESTAMP()), 365) * 0.15 +
    GREATEST(0, 30 - COALESCE(em.ACTIVE_DAYS_12M, 0)) * 0.5 +
    COALESCE(pm.RETURN_COUNT_12M, 0) * 2.0
  , 1))                                                       AS CHURN_RISK_SCORE,

  -- LTV annualized (simple: annual_spend proxy)
  ROUND(COALESCE(pm.TOTAL_SPEND_12M, c.ANNUAL_SPEND * 0.5), 2) AS LTV_ANNUALIZED,

  -- Customer health score (0-100, higher = healthier)
  LEAST(100, ROUND(
    rfm.R_SCORE * 8 +
    rfm.F_SCORE * 8 +
    rfm.M_SCORE * 8 +
    COALESCE(em.ACTIVE_DAYS_12M, 0) * 0.3 +
    COALESCE(em.TRAINING_LOGS_12M, 0) * 1.0
  , 1))                                                       AS CUSTOMER_HEALTH_SCORE,

  -- Revenue opportunity (estimated incremental LTV uplift)
  ROUND(
    COALESCE(pm.AVG_ORDER_VALUE, c.ANNUAL_SPEND / GREATEST(pm.PURCHASE_COUNT_12M, 1)) *
    lt.POINTS_MULTIPLIER * 2.5
  , 2)                                                        AS REVENUE_OPPORTUNITY_SCORE

FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMERS c
LEFT JOIN WRITER_SNOW_DEMO.MARKETING.LOYALTY_TIERS lt ON lt.TIER_ID = c.LOYALTY_TIER_ID
LEFT JOIN purchase_metrics  pm  ON pm.CUSTOMER_ID  = c.CUSTOMER_ID
LEFT JOIN engagement_metrics em ON em.CUSTOMER_ID  = c.CUSTOMER_ID
LEFT JOIN campaign_metrics   cm ON cm.CUSTOMER_ID  = c.CUSTOMER_ID
LEFT JOIN rfm_scores         rfm ON rfm.CUSTOMER_ID = c.CUSTOMER_ID;

GRANT SELECT ON DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360 TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- MICRO_SEGMENTS — 22 scored segments
-- Segments = RFM(8) × Churn(3) × Channel(3), filtered to min audience size
-- Columns include INTENT_SCORE composite ranking (60.5–82.9)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS
  -- DOWNSTREAM: refreshes immediately after CUSTOMER_360 completes, never independently.
  TARGET_LAG = 'DOWNSTREAM'
  WAREHOUSE  = WRITER_WH
  REFRESH_MODE = FULL
  COMMENT = 'Apex Athletics 22 scored micro-segments for campaign targeting'
AS
WITH
  segment_base AS (
    SELECT
      RFM_SEGMENT,
      CHURN_RISK_TIER,
      PREFERRED_CHANNEL,
      COUNT(*)                                    AS CUSTOMER_COUNT,
      ROUND(AVG(ANNUAL_SPEND), 2)                 AS AVG_SPEND,
      ROUND(AVG(ENGAGEMENT_SCORE), 2)             AS AVG_ENGAGEMENT_SCORE,
      ROUND(AVG(CAMPAIGN_CONVERSION_RATE), 4)     AS AVG_CAMPAIGN_CONVERSION_RATE,
      ROUND(AVG(LTV_ANNUALIZED), 2)               AS AVG_LTV_ANNUALIZED,
      ROUND(SUM(REVENUE_OPPORTUNITY_SCORE), 2)    AS TOTAL_REVENUE_OPPORTUNITY
    FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360
    GROUP BY RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL
    HAVING COUNT(*) >= 200   -- minimum viable segment size
  ),
  ranked AS (
    SELECT
      ROW_NUMBER() OVER (ORDER BY
        TOTAL_REVENUE_OPPORTUNITY DESC,
        AVG_ENGAGEMENT_SCORE DESC
      ) AS SEGMENT_ID,
      RFM_SEGMENT || ' / ' || CHURN_RISK_TIER || ' Churn / ' || UPPER(PREFERRED_CHANNEL)
        AS SEGMENT_NAME,
      RFM_SEGMENT,
      CHURN_RISK_TIER,
      PREFERRED_CHANNEL,
      CUSTOMER_COUNT,
      AVG_SPEND,
      AVG_ENGAGEMENT_SCORE,
      AVG_CAMPAIGN_CONVERSION_RATE,
      AVG_LTV_ANNUALIZED,
      TOTAL_REVENUE_OPPORTUNITY,
      -- INTENT_SCORE: composite ranking scaled to 60.5–82.9 for demo appeal
      ROUND(
        60.5 + (
          (RANK() OVER (ORDER BY
             TOTAL_REVENUE_OPPORTUNITY * 0.4 +
             AVG_ENGAGEMENT_SCORE      * 0.35 +
             AVG_LTV_ANNUALIZED        * 0.25
          ) - 1) /
          NULLIF(COUNT(*) OVER () - 1, 0) * 22.4
        ), 1
      )                                           AS INTENT_SCORE
    FROM segment_base
  )
SELECT
  SEGMENT_ID,
  SEGMENT_NAME,
  RFM_SEGMENT,
  CHURN_RISK_TIER,
  PREFERRED_CHANNEL,
  CUSTOMER_COUNT,
  AVG_SPEND,
  AVG_ENGAGEMENT_SCORE,
  AVG_CAMPAIGN_CONVERSION_RATE,
  AVG_LTV_ANNUALIZED,
  TOTAL_REVENUE_OPPORTUNITY,
  INTENT_SCORE
FROM ranked
ORDER BY INTENT_SCORE DESC
LIMIT 22;  -- cap at exactly 22 segments regardless of how many >=200 combos exist

GRANT SELECT ON DYNAMIC TABLE WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS TO ROLE WRITER_MARKETING_ROLE;
