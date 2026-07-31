-- =============================================================================
-- 03_data_model.sql  —  Apex Athletics Content Supply Chain
-- Step 3 of 6
--
-- Creates:
--   • CUSTOMER_360 Dynamic Table (65 cols, 1-day lag, FULL refresh)
--   • MICRO_SEGMENTS Dynamic Table (22 scored segments, DOWNSTREAM lag)
--   • CAMPAIGN_LIBRARY (100 AI-generated historical campaigns)
--   • CAMPAIGN_BRIEFS, CONTENT_ASSETS, CAMPAIGN_AUDIENCES (write-back tables)
--   • ACTIVATE_SEGMENT, SAVE_BRIEF, SAVE_CONTENT_ASSET stored procedures
--
-- Note: Dynamic Tables initialize in background after creation.
--       Campaign library generation uses claude-haiku-4-5 — requires Cortex AI.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;


-- ──────────────────────────────────────────────────────────────────────────
-- DYNAMIC TABLES  (from 04_dynamic_tables.sql)
-- ──────────────────────────────────────────────────────────────────────────
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

-- ──────────────────────────────────────────────────────────────────────────
-- CAMPAIGN LIBRARY — AI-generated content  (from 05_campaign_library.sql)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY (
  CAMPAIGN_ID            VARCHAR(15)   NOT NULL,
  CAMPAIGN_NAME          VARCHAR(100)  NOT NULL,
  BRIEF_ID               VARCHAR(20),
  TARGET_SEGMENT         VARCHAR(100),
  CAMPAIGN_TYPE          VARCHAR(30)   NOT NULL,
  CHANNEL                VARCHAR(20)   NOT NULL,
  SUBJECT_LINE           VARCHAR(200),
  BODY_PREVIEW           VARCHAR(500),
  CTA_TEXT               VARCHAR(100),
  TONE                   VARCHAR(50),
  PERFORMANCE_TIER       VARCHAR(20),   -- Starter / Active / Performance / Elite
  OPEN_RATE              NUMBER(5,4),
  CLICK_RATE             NUMBER(5,4),
  CONVERSION_RATE        NUMBER(5,4),
  REVENUE_GENERATED      NUMBER(12,2),
  CREATED_DATE           DATE,
  LAST_USED_DATE         DATE,
  TAGS                   VARCHAR(500)
);

-- Generate 100 campaigns using CORTEX.COMPLETE for authentic activewear content.
-- Batched in groups to avoid rate limits.
-- Group 1: CMP-2025-001 to CMP-2025-020 — Welcome Series (001-005) + Re-engagement (006-015) + Seasonal (016-020)
INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY
WITH
  campaign_seeds AS (
    SELECT * FROM VALUES
      -- Welcome Series (CMP-2025-001 to 005)
      ('CMP-2025-001','Welcome_Series_Email_1',      'BRF-001', 'New Customers',          'Welcome',        'email', 'Starter',   'Welcome to Apex Athletics! Discover Your Performance Journey', 0.42, 0.18, 0.21, 0.87),
      ('CMP-2025-002','Welcome_Series_Push_1',       'BRF-001', 'New Customers',          'Welcome',        'push',  'Starter',   'Welcome to Apex Athletics! Your first reward is waiting',      0.38, 0.22, 0.19, 0.83),
      ('CMP-2025-003','Welcome_Series_SMS_1',        'BRF-001', 'New Customers',          'Welcome',        'sms',   'Starter',   'Welcome to Apex! Claim your 10% new member discount today',   0.45, 0.25, 0.23, 0.91),
      ('CMP-2025-004','Welcome_Category_Email',      'BRF-002', 'New Customers',          'Welcome',        'email', 'Active',    'We picked these just for you based on your interests',         0.35, 0.19, 0.17, 0.76),
      ('CMP-2025-005','Welcome_First_Purchase',      'BRF-002', 'New Customers',          'Welcome',        'email', 'Active',    'Your first purchase starts here — 10% off everything',         0.40, 0.21, 0.20, 0.84),
      -- Re-engagement (CMP-2025-006 to 015)
      ('CMP-2025-006','Winback_Email_1',             'BRF-003', 'At Risk / High Churn',   'Re-engagement',  'email', 'Active',    'We miss your energy! Here''s 25% off to welcome you back',    0.14, 0.08, 0.07, 0.65),
      ('CMP-2025-007','Winback_Email_2',             'BRF-003', 'At Risk / High Churn',   'Re-engagement',  'email', 'Active',    'Still thinking about that running shoe? It''s almost gone',   0.12, 0.07, 0.06, 0.58),
      ('CMP-2025-008','Winback_Push_1',              'BRF-003', 'At Risk / High Churn',   'Re-engagement',  'push',  'Active',    'Come back to your goals — 3 new drops just for you',           0.16, 0.10, 0.08, 0.70),
      ('CMP-2025-009','Winback_Retargeting',         'BRF-003', 'Dormant / High Churn',   'Re-engagement',  'social','Starter',   'Your last category is waiting at a special price',             0.09, 0.05, 0.04, 0.48),
      ('CMP-2025-010','Winback_LastChance',          'BRF-004', 'Dormant / High Churn',   'Re-engagement',  'email', 'Starter',   'Last chance: your exclusive win-back offer expires tonight',   0.11, 0.06, 0.05, 0.52),
      ('CMP-2025-011','Winback_Social_Proof',        'BRF-004', 'At Risk / High Churn',   'Re-engagement',  'email', 'Active',    '4,200 athletes chose Apex last week. Here''s why they love it', 0.13, 0.08, 0.07, 0.62),
      ('CMP-2025-012','Winback_Category_Recs',       'BRF-004', 'At Risk / High Churn',   'Re-engagement',  'email', 'Active',    'New arrivals in your favorite category — just for you',        0.15, 0.09, 0.08, 0.68),
      ('CMP-2025-013','Winback_Loyalty_Nudge',       'BRF-005', 'Dormant / High Churn',   'Re-engagement',  'email', 'Starter',   'You''re 200 points from your next reward — don''t lose them', 0.10, 0.06, 0.05, 0.50),
      ('CMP-2025-014','Winback_Bundle_Offer',        'BRF-005', 'Dormant / High Churn',   'Re-engagement',  'email', 'Active',    'Train smarter: bundle 2 items and save 30%',                  0.12, 0.07, 0.06, 0.55),
      ('CMP-2025-015','Winback_Free_Shipping',       'BRF-005', 'Dormant / High Churn',   'Re-engagement',  'email', 'Active',    'Free shipping on your comeback order — no minimum',            0.11, 0.06, 0.05, 0.51),
      -- Seasonal (CMP-2025-016 to 025)
      ('CMP-2025-016','Marathon_Season_Kickoff',     'BRF-006', 'Champion / Low Churn',   'Seasonal',       'email', 'Performance','Race day is coming. Here''s your performance gear checklist', 0.32, 0.15, 0.12, 0.95),
      ('CMP-2025-017','Marathon_TrainingPlan',       'BRF-006', 'Loyal / Low Churn',      'Seasonal',       'email', 'Active',    'Your 12-week marathon prep guide — plus the gear you need',    0.28, 0.13, 0.11, 0.88),
      ('CMP-2025-018','Marathon_Social_Running',     'BRF-006', 'Recent / Low Churn',     'Seasonal',       'social','Active',    'Tag us in your training run to win exclusive gear',            0.22, 0.18, 0.08, 0.75),
      ('CMP-2025-019','New_Year_Fitness',            'BRF-007', 'New Customers',          'Seasonal',       'email', 'Performance','2025 starts now. Build your best-performing year in gear',    0.35, 0.16, 0.14, 0.98),
      ('CMP-2025-020','New_Year_Goals',              'BRF-007', 'Recent / Low Churn',     'Seasonal',       'email', 'Active',    'Set your 2025 goal. We''ll help you gear up for it',           0.30, 0.14, 0.11, 0.90)
    AS s(CAMPAIGN_ID, CAMPAIGN_NAME, BRIEF_ID, TARGET_SEGMENT, CAMPAIGN_TYPE, CHANNEL, PERFORMANCE_TIER, CONTEXT, OPEN_RATE, CLICK_RATE, CONVERSION_RATE, AVG_REVENUE_K)
  )
SELECT
  s.CAMPAIGN_ID,
  s.CAMPAIGN_NAME,
  s.BRIEF_ID,
  s.TARGET_SEGMENT,
  s.CAMPAIGN_TYPE,
  s.CHANNEL,
  -- AI-generated subject line for authentic content
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a compelling marketing email subject line for an activewear brand called Apex Athletics. ' ||
    'Campaign type: ' || s.CAMPAIGN_TYPE || '. Target segment: ' || s.TARGET_SEGMENT || '. ' ||
    'Context: ' || s.CONTEXT || '. ' ||
    'Return ONLY the subject line text, no quotes, no explanation, max 60 characters.'
  ))                                                              AS SUBJECT_LINE,
  -- AI-generated body preview
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 1-2 sentence email preview for an activewear brand Apex Athletics. ' ||
    'Campaign: ' || s.CAMPAIGN_NAME || '. Target: ' || s.TARGET_SEGMENT || '. ' ||
    'Tone: ' || s.PERFORMANCE_TIER || ' performance level. ' ||
    'Return ONLY the preview text, no quotes, max 150 characters.'
  ))                                                              AS BODY_PREVIEW,
  -- AI-generated CTA
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 3-6 word call-to-action button text for an activewear campaign targeting ' || s.TARGET_SEGMENT || '. Campaign: ' || s.CAMPAIGN_TYPE || '. Return ONLY the CTA text.'
  ))                                                              AS CTA_TEXT,
  CASE s.PERFORMANCE_TIER
    WHEN 'Performance' THEN 'technical'
    WHEN 'Elite'       THEN 'premium'
    WHEN 'Active'      THEN 'motivational'
    ELSE 'friendly'
  END                                                             AS TONE,
  s.PERFORMANCE_TIER,
  s.OPEN_RATE,
  s.CLICK_RATE,
  s.CONVERSION_RATE,
  ROUND(UNIFORM(1000, 45000, RANDOM()), 2)                       AS REVENUE_GENERATED,
  DATEADD(day, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE())      AS CREATED_DATE,
  DATEADD(day, -UNIFORM(0,  60,  RANDOM()), CURRENT_DATE())      AS LAST_USED_DATE,
  s.CAMPAIGN_TYPE || ',' || s.TARGET_SEGMENT || ',' || s.CHANNEL AS TAGS
FROM campaign_seeds s;

-- Group 2: CMP-2025-021 to CMP-2025-060 — Seasonal cont. + Product Launch + Win-Back
INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY
WITH
  campaign_seeds AS (
    SELECT * FROM VALUES
      ('CMP-2025-021','Summer_Training_Launch',    'BRF-008','Needs Attention / Low Churn','Seasonal',      'email','Active',     'Gear up for summer training — hot weather, peak performance', 0.29, 0.14, 0.11, 0.87),
      ('CMP-2025-022','Summer_Outdoor_Social',     'BRF-008','Recent / Low Churn',         'Seasonal',      'social','Active',    'Your summer trail run starts with the right gear',            0.24, 0.20, 0.09, 0.78),
      ('CMP-2025-023','BackGym_September',         'BRF-009','New Customers',              'Seasonal',      'email', 'Active',    'September reset: refresh your gym wardrobe this fall',        0.31, 0.15, 0.12, 0.91),
      ('CMP-2025-024','Holiday_Gift_Guide',        'BRF-009','Champion / Low Churn',       'Seasonal',      'email', 'Performance','The Apex Athletics gift guide for athletes who have everything', 0.38, 0.17, 0.15, 1.20),
      ('CMP-2025-025','Holiday_Bundle_Email',      'BRF-009','Loyal / Low Churn',          'Seasonal',      'email', 'Performance','Gift sets built for peak performance — curated for your athlete', 0.35, 0.16, 0.13, 1.10),
      -- Product Launch (CMP-2025-026 to 040)
      ('CMP-2025-026','TrailBlazer_X1_Reveal',     'BRF-010','Competitive Runners',        'Product Launch','email', 'Performance','Introducing TrailBlazer X1: the trail shoe that outperforms', 0.40, 0.20, 0.16, 1.50),
      ('CMP-2025-027','TrailBlazer_X1_IG',         'BRF-010','Outdoor Enthusiasts',        'Product Launch','social','Active',    'The trail demands more. The TrailBlazer X1 delivers it',      0.33, 0.28, 0.12, 1.20),
      ('CMP-2025-028','TrailBlazer_X1_Influencer', 'BRF-010','Outdoor Enthusiasts',        'Product Launch','social','Performance','Your next PR starts on the trail with TrailBlazer X1',        0.36, 0.30, 0.14, 1.35),
      ('CMP-2025-029','Yoga_Collection_Launch',    'BRF-011','Yoga Enthusiasts',           'Product Launch','email', 'Active',    'New yoga collection: where comfort meets performance',         0.38, 0.19, 0.15, 1.10),
      ('CMP-2025-030','Yoga_Collection_Social',    'BRF-011','Yoga Enthusiasts',           'Product Launch','social','Active',    'Flow freely in our new seamless yoga collection',             0.31, 0.26, 0.11, 0.95),
      ('CMP-2025-031','Compression_Pro_Launch',    'BRF-012','Training Athletes',          'Product Launch','email', 'Active',    'Train harder, recover faster: introducing Compression Pro',   0.35, 0.16, 0.13, 1.05),
      ('CMP-2025-032','Recovery_Wear_Launch',      'BRF-012','Recovery Focused',           'Product Launch','email', 'Active',    'Recover smarter: new recovery wear engineered for athletes',  0.33, 0.15, 0.12, 0.98),
      ('CMP-2025-033','Weather_Jacket_Launch',     'BRF-012','Outdoor Enthusiasts',        'Product Launch','email', 'Performance','Run through anything: our most technical weather jacket yet', 0.37, 0.18, 0.14, 1.30),
      ('CMP-2025-034','New_Drop_Elite_Preview',    'BRF-013','Elite Members',              'Product Launch','email', 'Elite',     'You''re first: 48-hour elite access to our spring drop',      0.55, 0.32, 0.28, 2.10),
      ('CMP-2025-035','New_Drop_SMS_Alert',        'BRF-013','Champion / Low Churn',       'Product Launch','sms',   'Performance','Spring drop live now. Shop before it sells out',             0.60, 0.40, 0.32, 2.50),
      ('CMP-2025-036','Product_Launch_LandingPage','BRF-014','Recent / Low Churn',         'Product Launch','web',   'Active',    'Discover the spring performance collection at Apex Athletics', 0.25, 0.15, 0.10, 0.85),
      ('CMP-2025-037','Bra_Performance_Launch',    'BRF-014','Yoga Enthusiasts',           'Product Launch','email', 'Active',    'Engineered support for every move: new sports bra collection', 0.36, 0.18, 0.14, 1.05),
      ('CMP-2025-038','Running_Apparel_Refresh',   'BRF-014','Competitive Runners',        'Product Launch','email', 'Active',    'Lighter. Faster. More breathable. See the new running line',  0.39, 0.19, 0.16, 1.15),
      ('CMP-2025-039','Athleisure_Drop',           'BRF-015','Lifestyle Athletes',         'Product Launch','social','Active',    'Style and performance collide in our new athleisure drop',    0.28, 0.24, 0.10, 0.90),
      ('CMP-2025-040','Socks_Accessories_Refresh', 'BRF-015','Active Customers',           'Product Launch','email', 'Starter',   'The details matter: new socks and training accessories',      0.22, 0.10, 0.08, 0.65),
      -- Win-Back (CMP-2025-041 to 060)
      ('CMP-2025-041','Winback_Elite_Exclusive',   'BRF-016','Dormant / Elite',            'Win-Back',      'email', 'Elite',     'Your Elite status is waiting — come back for an exclusive drop', 0.18, 0.10, 0.09, 0.85),
      ('CMP-2025-042','Winback_Training_Focus',    'BRF-016','Dormant / High Churn',       'Win-Back',      'email', 'Active',    'Your training is calling. Here''s the gear to answer it',     0.13, 0.07, 0.06, 0.60),
      ('CMP-2025-043','Winback_New_Drop_Alert',    'BRF-016','Dormant / High Churn',       'Win-Back',      'email', 'Active',    'You missed this last season. Don''t miss it again',           0.14, 0.08, 0.07, 0.65),
      ('CMP-2025-044','Winback_Yoga_Loyal',        'BRF-017','Dormant / Yoga Segment',     'Win-Back',      'email', 'Active',    'Your practice misses you — and so do we',                     0.16, 0.09, 0.08, 0.70),
      ('CMP-2025-045','Winback_Runner_Comeback',   'BRF-017','Dormant / Running Segment',  'Win-Back',      'email', 'Active',    'Your next race deserves better gear. We''ll help you get there', 0.15, 0.08, 0.07, 0.68),
      ('CMP-2025-046','Winback_Milestone_Offer',   'BRF-017','At Risk / High Churn',       'Win-Back',      'email', 'Active',    'You''re 1 purchase from Performance tier. We''ll make it easy', 0.17, 0.10, 0.09, 0.80),
      ('CMP-2025-047','Winback_Trail_Seekers',     'BRF-018','Dormant / Outdoor Segment',  'Win-Back',      'email', 'Active',    'Adventure is waiting. So is your win-back offer',             0.14, 0.08, 0.06, 0.62),
      ('CMP-2025-048','Winback_Recovery_Segment',  'BRF-018','Dormant / Recovery Segment', 'Win-Back',      'email', 'Active',    'Your recovery routine deserves an upgrade. 20% off today',    0.13, 0.07, 0.06, 0.58),
      ('CMP-2025-049','Winback_Social_Proof_V2',   'BRF-018','At Risk / High Churn',       'Win-Back',      'email', 'Active',    'Join 50,000 athletes who chose Apex this season',             0.15, 0.09, 0.08, 0.72),
      ('CMP-2025-050','Winback_Urgency_Final',     'BRF-019','Dormant / High Churn',       'Win-Back',      'email', 'Starter',   'This is our final offer before we reset your rewards',        0.10, 0.05, 0.04, 0.45),
      ('CMP-2025-051','Winback_Bundle_V2',         'BRF-019','Dormant / High Churn',       'Win-Back',      'email', 'Active',    'Build your comeback bundle: buy 2 items, save 25%',           0.12, 0.07, 0.06, 0.56),
      ('CMP-2025-052','Winback_Lifestyle_Segment', 'BRF-019','Dormant / Lifestyle',        'Win-Back',      'social','Active',    'The style you loved is back — and better than ever',          0.10, 0.09, 0.05, 0.50),
      ('CMP-2025-053','Winback_Cart_Miss',         'BRF-020','At Risk / Cart Abandoners',  'Win-Back',      'email', 'Active',    'You left something great behind. It''s still here for you',   0.18, 0.11, 0.10, 0.90),
      ('CMP-2025-054','Winback_Personalized_Recs', 'BRF-020','At Risk / High Churn',       'Win-Back',      'email', 'Active',    'Handpicked for you based on your past purchases',             0.16, 0.09, 0.08, 0.75),
      ('CMP-2025-055','Winback_Milestone_Elite',   'BRF-020','Dormant / Elite',            'Win-Back',      'email', 'Elite',     'Your VIP status shouldn''t go to waste. Here''s your reward', 0.20, 0.12, 0.11, 1.00),
      ('CMP-2025-056','Winback_Seasonal_Trigger',  'BRF-021','Dormant / High Churn',       'Win-Back',      'email', 'Active',    'The season is changing. Is your training wardrobe ready?',    0.14, 0.08, 0.07, 0.63),
      ('CMP-2025-057','Winback_SMS_Alert',         'BRF-021','At Risk / High Churn',       'Win-Back',      'sms',   'Active',    'We''re still here for you — 25% off for the next 48 hours',   0.45, 0.28, 0.20, 1.80),
      ('CMP-2025-058','Winback_Push_Last',         'BRF-021','Dormant / High Churn',       'Win-Back',      'push',  'Starter',   'Final nudge: your comeback offer expires at midnight',         0.22, 0.14, 0.10, 0.92),
      ('CMP-2025-059','Winback_Category_Trail',    'BRF-022','At Risk / Outdoor',          'Win-Back',      'email', 'Active',    'New trail gear just dropped — made for runners like you',      0.17, 0.10, 0.08, 0.78),
      ('CMP-2025-060','Winback_Recovery_Special',  'BRF-022','Dormant / Recovery',         'Win-Back',      'email', 'Active',    'Your body deserves the best recovery gear. Here''s 20% off',  0.14, 0.08, 0.07, 0.65)
    AS s(CAMPAIGN_ID, CAMPAIGN_NAME, BRIEF_ID, TARGET_SEGMENT, CAMPAIGN_TYPE, CHANNEL, PERFORMANCE_TIER, CONTEXT, OPEN_RATE, CLICK_RATE, CONVERSION_RATE, AVG_REVENUE_K)
  )
SELECT
  s.CAMPAIGN_ID,
  s.CAMPAIGN_NAME,
  s.BRIEF_ID,
  s.TARGET_SEGMENT,
  s.CAMPAIGN_TYPE,
  s.CHANNEL,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a compelling marketing email subject line for activewear brand Apex Athletics. ' ||
    'Campaign: ' || s.CAMPAIGN_TYPE || '. Target: ' || s.TARGET_SEGMENT || '. ' ||
    'Context: ' || s.CONTEXT || '. Return ONLY the subject line, no quotes, max 60 chars.'
  ))                                                              AS SUBJECT_LINE,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 1-2 sentence email body preview for Apex Athletics activewear. ' ||
    'Campaign: ' || s.CAMPAIGN_NAME || '. Target: ' || s.TARGET_SEGMENT || '. ' ||
    'Return ONLY the preview text, no quotes, max 150 chars.'
  ))                                                              AS BODY_PREVIEW,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 3-6 word CTA button for activewear campaign targeting ' || s.TARGET_SEGMENT || '. Type: ' || s.CAMPAIGN_TYPE || '. Return ONLY the CTA.'
  ))                                                              AS CTA_TEXT,
  CASE s.PERFORMANCE_TIER
    WHEN 'Performance' THEN 'technical'
    WHEN 'Elite'       THEN 'premium'
    WHEN 'Active'      THEN 'motivational'
    ELSE 'friendly'
  END                                                             AS TONE,
  s.PERFORMANCE_TIER,
  s.OPEN_RATE,
  s.CLICK_RATE,
  s.CONVERSION_RATE,
  ROUND(UNIFORM(2000, 80000, RANDOM()), 2)                       AS REVENUE_GENERATED,
  DATEADD(day, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE())      AS CREATED_DATE,
  DATEADD(day, -UNIFORM(0,  60,  RANDOM()), CURRENT_DATE())      AS LAST_USED_DATE,
  s.CAMPAIGN_TYPE || ',' || s.TARGET_SEGMENT || ',' || s.CHANNEL AS TAGS
FROM campaign_seeds s;

-- Group 3: CMP-2025-061 to CMP-2025-100 — Loyalty/VIP + Cart Abandonment
INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY
WITH
  campaign_seeds AS (
    SELECT * FROM VALUES
      -- Loyalty / VIP (CMP-2025-061 to 080)
      ('CMP-2025-061','Elite_EarlyAccess_Spring',  'BRF-023','Elite Members',             'Loyalty',       'email', 'Elite',     'Elite-only: 48 hours early access to spring drop',           0.58, 0.35, 0.30, 2.80),
      ('CMP-2025-062','VIP_EventInvite',           'BRF-023','Elite Members',             'Loyalty',       'email', 'Elite',     'You''re invited: VIP training session with Apex coaches',    0.52, 0.28, 0.22, 1.90),
      ('CMP-2025-063','Performance_PointsBonus',   'BRF-024','Performance Members',       'Loyalty',       'email', 'Performance','Double points this weekend — shop your favorite category',  0.45, 0.24, 0.20, 1.60),
      ('CMP-2025-064','Loyalty_Milestone_500',     'BRF-024','Active Members',            'Loyalty',       'email', 'Active',    'You just hit 500 points! Here''s what you can redeem',       0.50, 0.30, 0.25, 2.00),
      ('CMP-2025-065','Loyalty_Birthday_Reward',   'BRF-024','All Loyalty Members',       'Loyalty',       'email', 'Active',    'Happy birthday from Apex — your gift is ready to claim',     0.62, 0.38, 0.32, 2.60),
      ('CMP-2025-066','Elite_Exclusive_Drop',      'BRF-025','Elite Members',             'Loyalty',       'email', 'Elite',     'Limited drop alert: reserved for Elite members only',        0.60, 0.40, 0.36, 3.20),
      ('CMP-2025-067','VIP_FreeShipping_All',      'BRF-025','Performance Members',       'Loyalty',       'email', 'Performance','Performance perk: free shipping on every order this month',  0.48, 0.26, 0.21, 1.70),
      ('CMP-2025-068','Loyalty_Tier_Upgrade',      'BRF-025','Active Members',            'Loyalty',       'email', 'Active',    'You''re close to Performance tier — here''s how to unlock it', 0.44, 0.23, 0.18, 1.40),
      ('CMP-2025-069','Elite_Personal_Stylist',    'BRF-026','Elite Members',             'Loyalty',       'email', 'Elite',     'Your personal Apex curator has handpicked next season',      0.55, 0.32, 0.27, 2.20),
      ('CMP-2025-070','VIP_Training_Content',      'BRF-026','Performance Members',       'Loyalty',       'email', 'Performance','Member-only training plan from our Apex Coaches',            0.42, 0.22, 0.17, 1.30),
      ('CMP-2025-071','Loyalty_Push_PointsExpiry', 'BRF-026','Active Members',            'Loyalty',       'push',  'Active',    'Your 200 points expire soon — redeem before they''re gone',  0.38, 0.28, 0.22, 1.75),
      ('CMP-2025-072','Elite_SMS_Drop_Alert',      'BRF-027','Elite Members',             'Loyalty',       'sms',   'Elite',     'Elite drop live. You have first access for 2 hours only',   0.68, 0.50, 0.42, 3.80),
      ('CMP-2025-073','VIP_Summer_Preview',        'BRF-027','Elite Members',             'Loyalty',       'email', 'Elite',     'Summer preview: Elite members shop first. Always.',          0.56, 0.34, 0.29, 2.40),
      ('CMP-2025-074','Loyalty_App_Exclusive',     'BRF-027','Performance Members',       'Loyalty',       'push',  'Performance','App exclusive: 15% off for 24 hours. Performance members only', 0.44, 0.32, 0.26, 2.10),
      ('CMP-2025-075','Loyalty_Referral_Offer',    'BRF-028','Active Members',            'Loyalty',       'email', 'Active',    'Refer a friend — you both get rewarded',                     0.36, 0.20, 0.15, 1.20),
      ('CMP-2025-076','Elite_Athlete_Collab',      'BRF-028','Elite Members',             'Loyalty',       'email', 'Elite',     'Co-designed with pro athletes — available to Elite first',   0.54, 0.32, 0.27, 2.30),
      ('CMP-2025-077','VIP_Exclusive_Training',    'BRF-028','Elite Members',             'Loyalty',       'email', 'Elite',     'Train with the team: invite to our virtual VIP session',     0.50, 0.28, 0.20, 1.60),
      ('CMP-2025-078','Loyalty_Year_End',          'BRF-029','All Loyalty Members',       'Loyalty',       'email', 'Performance','Your year with Apex: milestones, points, and what''s next',  0.46, 0.24, 0.19, 1.50),
      ('CMP-2025-079','Elite_Holiday_VIP',         'BRF-029','Elite Members',             'Loyalty',       'email', 'Elite',     'Holiday VIP experience: curated bundle + exclusive drop',    0.60, 0.38, 0.32, 2.90),
      ('CMP-2025-080','Loyalty_Push_Milestone',    'BRF-029','Active Members',            'Loyalty',       'push',  'Active',    'You hit a new milestone! Here''s a surprise reward',         0.42, 0.30, 0.24, 1.95),
      -- Cart Abandonment (CMP-2025-081 to 100)
      ('CMP-2025-081','Cart_2hr_Reminder',         'BRF-030','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Still thinking about it? Your cart is saved',               0.28, 0.14, 0.12, 1.10),
      ('CMP-2025-082','Cart_24hr_Urgency',         'BRF-030','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Selling fast — your cart item is almost gone',               0.24, 0.12, 0.10, 0.95),
      ('CMP-2025-083','Cart_72hr_LastChance',      'BRF-030','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Last chance to complete your order — and save 10%',          0.20, 0.10, 0.08, 0.80),
      ('CMP-2025-084','Cart_Push_Immediate',       'BRF-031','Cart Abandoners',           'Cart Abandon',  'push',  'Active',    'Your cart is waiting — check out in 1 tap',                  0.35, 0.25, 0.18, 1.45),
      ('CMP-2025-085','Cart_SMS_Alert',            'BRF-031','Cart Abandoners',           'Cart Abandon',  'sms',   'Active',    'Someone else is eyeing your cart. Grab it now',              0.48, 0.32, 0.24, 1.95),
      ('CMP-2025-086','Cart_Social_Proof',         'BRF-031','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    '2,100 athletes bought this last week. Here''s why',          0.22, 0.11, 0.09, 0.88),
      ('CMP-2025-087','Cart_Free_Shipping_Offer',  'BRF-032','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Complete your order — free shipping, no minimum needed',     0.26, 0.13, 0.11, 1.05),
      ('CMP-2025-088','Cart_Review_Boost',         'BRF-032','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'See what 4.8-star reviewers say about your saved item',      0.24, 0.12, 0.10, 0.95),
      ('CMP-2025-089','Cart_Size_Reassurance',     'BRF-032','Cart Abandoners',           'Cart Abandon',  'email', 'Starter',   'Not sure about the size? Our fit guide can help',            0.20, 0.10, 0.08, 0.78),
      ('CMP-2025-090','Cart_Elite_Exclusive',      'BRF-033','Elite Cart Abandoners',     'Cart Abandon',  'email', 'Elite',     'Your Elite cart is reserved — complimentary gift with purchase', 0.40, 0.22, 0.18, 1.75),
      ('CMP-2025-091','Cart_Seasonal_Urgency',     'BRF-033','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Season''s changing — this gear sells out every year',        0.23, 0.12, 0.10, 0.96),
      ('CMP-2025-092','Cart_Bundle_Upsell',        'BRF-033','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Add one more item and save 20% on your entire cart',         0.25, 0.13, 0.11, 1.08),
      ('CMP-2025-093','Cart_Inventory_Alert',      'BRF-034','Cart Abandoners',           'Cart Abandon',  'push',  'Active',    'Low stock alert on your saved item — only 3 left',           0.38, 0.26, 0.20, 1.60),
      ('CMP-2025-094','Cart_Retargeting_Meta',     'BRF-034','Cart Abandoners',           'Cart Abandon',  'social','Active',    'You left something great behind. Here it is again',           0.12, 0.10, 0.07, 0.68),
      ('CMP-2025-095','Cart_Google_Retarget',      'BRF-034','Cart Abandoners',           'Cart Abandon',  'web',   'Active',    'Come back to your performance gear at Apex Athletics',       0.08, 0.06, 0.05, 0.48),
      ('CMP-2025-096','Cart_Recovery_Sequence_1',  'BRF-035','Recovery Cart Abandoners',  'Cart Abandon',  'email', 'Active',    'Your recovery gear is still in your cart — and worth it',   0.25, 0.13, 0.10, 0.99),
      ('CMP-2025-097','Cart_Yoga_Reminder',        'BRF-035','Yoga Cart Abandoners',      'Cart Abandon',  'email', 'Active',    'Your yoga essentials are waiting — complete your practice',  0.27, 0.14, 0.11, 1.06),
      ('CMP-2025-098','Cart_Running_Last',         'BRF-035','Running Cart Abandoners',   'Cart Abandon',  'email', 'Active',    'Your training run deserves this gear — it''s still here',   0.26, 0.13, 0.11, 1.02),
      ('CMP-2025-099','Cart_Trail_Reminder',       'BRF-036','Trail Cart Abandoners',     'Cart Abandon',  'email', 'Active',    'The trail is calling — your gear is ready to complete',      0.24, 0.12, 0.10, 0.96),
      ('CMP-2025-100','Cart_Points_Incentive',     'BRF-036','Cart Abandoners',           'Cart Abandon',  'email', 'Active',    'Complete your cart and earn triple points this week',        0.30, 0.16, 0.13, 1.25)
    AS s(CAMPAIGN_ID, CAMPAIGN_NAME, BRIEF_ID, TARGET_SEGMENT, CAMPAIGN_TYPE, CHANNEL, PERFORMANCE_TIER, CONTEXT, OPEN_RATE, CLICK_RATE, CONVERSION_RATE, AVG_REVENUE_K)
  )
SELECT
  s.CAMPAIGN_ID,
  s.CAMPAIGN_NAME,
  s.BRIEF_ID,
  s.TARGET_SEGMENT,
  s.CAMPAIGN_TYPE,
  s.CHANNEL,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a compelling marketing email subject line for activewear brand Apex Athletics. ' ||
    'Campaign: ' || s.CAMPAIGN_TYPE || '. Target: ' || s.TARGET_SEGMENT || '. ' ||
    'Context: ' || s.CONTEXT || '. Return ONLY the subject line, no quotes, max 60 chars.'
  ))                                                              AS SUBJECT_LINE,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 1-2 sentence email body preview for Apex Athletics activewear. ' ||
    'Campaign: ' || s.CAMPAIGN_NAME || '. Target: ' || s.TARGET_SEGMENT || '. ' ||
    'Return ONLY the preview text, no quotes, max 150 chars.'
  ))                                                              AS BODY_PREVIEW,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a 3-6 word CTA button for activewear campaign targeting ' || s.TARGET_SEGMENT || '. Type: ' || s.CAMPAIGN_TYPE || '. Return ONLY the CTA.'
  ))                                                              AS CTA_TEXT,
  CASE s.PERFORMANCE_TIER
    WHEN 'Performance' THEN 'technical'
    WHEN 'Elite'       THEN 'premium'
    WHEN 'Active'      THEN 'motivational'
    ELSE 'friendly'
  END                                                             AS TONE,
  s.PERFORMANCE_TIER,
  s.OPEN_RATE,
  s.CLICK_RATE,
  s.CONVERSION_RATE,
  ROUND(UNIFORM(3000, 120000, RANDOM()), 2)                      AS REVENUE_GENERATED,
  DATEADD(day, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE())      AS CREATED_DATE,
  DATEADD(day, -UNIFORM(0,  60,  RANDOM()), CURRENT_DATE())      AS LAST_USED_DATE,
  s.CAMPAIGN_TYPE || ',' || s.TARGET_SEGMENT || ',' || s.CHANNEL AS TAGS
FROM campaign_seeds s;

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY TO ROLE WRITER_MARKETING_ROLE;

-- ──────────────────────────────────────────────────────────────────────────
-- WRITE-BACK TABLES  (from 06_content_tables.sql)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS (
  BRIEF_ID      VARCHAR(50)    NOT NULL,
  CAMPAIGN_ID   VARCHAR(30),
  STATUS        VARCHAR(20)    DEFAULT 'draft',  -- draft/approved/archived
  CREATED_BY    VARCHAR(100),
  CREATED_AT    TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
  APPROVED_AT   TIMESTAMP_NTZ,
  BRIEF_CONTENT VARIANT        -- full brief JSON from Writer
);

-- Write-back table: Writer needs SELECT + INSERT
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CONTENT_ASSETS — Writer generates and writes these back via MCP save-asset
-- One row per discrete marketing asset generated by Writer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS (
  ASSET_ID          VARCHAR(50)   NOT NULL,
  BRIEF_ID          VARCHAR(50),
  CAMPAIGN_ID       VARCHAR(30),
  ASSET_TYPE        VARCHAR(30),   -- subject_line/email_body/social_post/ad_copy/landing_page/sms/push/blog
  CHANNEL           VARCHAR(20),   -- email/linkedin/meta/google/tiktok/sms/push/blog/web
  CONTENT_BODY      VARCHAR,       -- no length limit; blog posts and landing pages can be large
  HEADLINE          VARCHAR(500),
  CTA               VARCHAR(200),
  APPROVAL_STATUS   VARCHAR(20)   DEFAULT 'draft',  -- draft/in_review/approved/published/archived
  BRAND_VOICE_SCORE NUMBER(4,2),
  GENERATED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  REVIEWED_BY       VARCHAR(100),
  REVIEWED_AT       TIMESTAMP_NTZ,
  PUBLISHED_AT      TIMESTAMP_NTZ,
  PUBLISHED_URL     VARCHAR(500)
);

-- Write-back table: Writer needs SELECT + INSERT
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_AUDIENCES — Activation staging table (Reverse ETL target)
-- Written by ACTIVATE_SEGMENT stored procedure
-- Reverse ETL reads WHERE STATUS = 'pending' to push to Braze/SFMC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES (
  AUDIENCE_ID           NUMBER AUTOINCREMENT PRIMARY KEY,
  SEGMENT_ID            NUMBER        NOT NULL,
  SEGMENT_NAME          VARCHAR(200)  NOT NULL,
  CUSTOMER_ID           VARCHAR(12)   NOT NULL,
  EMAIL                 VARCHAR(100),
  FIRST_NAME            VARCHAR(50),
  PREFERRED_CHANNEL     VARCHAR(20),
  CAMPAIGN_NAME         VARCHAR(100)  NOT NULL,
  CAMPAIGN_CONTENT_ID   VARCHAR(30),   -- FK → CONTENT_ASSETS.ASSET_ID
  PRIORITY_RANK         NUMBER,
  STATUS                VARCHAR(20)   DEFAULT 'pending',  -- pending/activated/suppressed
  CREATED_AT            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  ACTIVATED_AT          TIMESTAMP_NTZ
);

-- Write-back table: ACTIVATE_SEGMENT proc writes here; Writer reads results
GRANT SELECT, INSERT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES TO ROLE WRITER_MARKETING_ROLE;

-- ──────────────────────────────────────────────────────────────────────────
-- STORED PROCEDURES  (from 07_stored_procedures.sql)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE WRITER_SNOW_DEMO.MARKETING.ACTIVATE_SEGMENT(
  P_SEGMENT_ID          NUMBER,
  P_CAMPAIGN_NAME       VARCHAR,
  P_CAMPAIGN_CONTENT_ID VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_segment_name  VARCHAR;
  v_staged_count  NUMBER;
  v_result        VARIANT;
  v_campaign_id   VARCHAR;
  v_cvr           FLOAT;
  v_open_rate     FLOAT;
  v_click_rate    FLOAT;
BEGIN
  -- Look up segment name and historical conversion rate for seeding
  SELECT SEGMENT_NAME, AVG_CAMPAIGN_CONVERSION_RATE
  INTO :v_segment_name, :v_cvr
  FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS
  WHERE SEGMENT_ID = :P_SEGMENT_ID;

  -- Rates with floor: activewear industry benchmarks (open 28%, click 12%, convert 5%)
  v_open_rate  := GREATEST(LEAST(:v_cvr * 5.0, 0.65), 0.28);
  v_click_rate := GREATEST(LEAST(:v_cvr * 2.5, 0.35), 0.12);
  v_cvr        := GREATEST(:v_cvr, 0.05);

  -- Resolve campaign_id: use content asset's campaign_id if provided,
  -- otherwise derive a short ID from campaign name (max 15 chars for CAMPAIGN_EVENTS)
  IF (:P_CAMPAIGN_CONTENT_ID IS NOT NULL) THEN
    SELECT CAMPAIGN_ID INTO :v_campaign_id
    FROM WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS
    WHERE ASSET_ID = :P_CAMPAIGN_CONTENT_ID;
  END IF;
  IF (:v_campaign_id IS NULL) THEN
    v_campaign_id := LEFT(REPLACE(UPPER(:P_CAMPAIGN_NAME), ' ', '-'), 15);
  END IF;

  -- ── Stage customers into CAMPAIGN_AUDIENCES ───────────────────────────────
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
    (SEGMENT_ID, SEGMENT_NAME, CUSTOMER_ID, EMAIL, FIRST_NAME, PREFERRED_CHANNEL,
     CAMPAIGN_NAME, CAMPAIGN_CONTENT_ID, PRIORITY_RANK, STATUS, CREATED_AT)
  SELECT
    :P_SEGMENT_ID, :v_segment_name,
    c.CUSTOMER_ID, c.EMAIL, c.FIRST_NAME, c.PREFERRED_CHANNEL,
    :P_CAMPAIGN_NAME, :P_CAMPAIGN_CONTENT_ID,
    ROW_NUMBER() OVER (ORDER BY c360.CUSTOMER_HEALTH_SCORE DESC),
    'pending', CURRENT_TIMESTAMP()
  FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360 c360
  JOIN WRITER_SNOW_DEMO.MARKETING.CUSTOMERS c ON c.CUSTOMER_ID = c360.CUSTOMER_ID
  WHERE c360.RFM_SEGMENT      = (SELECT RFM_SEGMENT      FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND c360.CHURN_RISK_TIER  = (SELECT CHURN_RISK_TIER  FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND c360.PREFERRED_CHANNEL = (SELECT PREFERRED_CHANNEL FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND NOT EXISTS (
      SELECT 1 FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES ca
      WHERE ca.CUSTOMER_ID = c.CUSTOMER_ID
        AND ca.CAMPAIGN_NAME = :P_CAMPAIGN_NAME
        AND ca.STATUS = 'pending'
    );

  SELECT COUNT(*) INTO :v_staged_count
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID = :P_SEGMENT_ID AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME AND STATUS = 'pending';

  -- ── Seed synthetic performance events (simulates Braze/SFMC return data) ──
  -- This closes the flywheel: activating a segment automatically generates
  -- realistic send/open/click/convert events that CAMPAIGN_PERFORMANCE_GOLD
  -- picks up on its next DT refresh.
  --
  -- Uses ABS(MOD(HASH(CUSTOMER_ID || salt), 1000)) for true per-row sampling.
  -- UNIFORM() in WHERE clauses evaluates once per batch (not per row) in procs.

  -- Sends — all staged customers
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
    (EVENT_ID, CAMPAIGN_ID, CUSTOMER_ID, EVENT_TYPE, EVENT_TIMESTAMP, CHANNEL, DEVICE_TYPE)
  SELECT
    'S' || LEFT(:v_campaign_id, 7) || 'S' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID), 11, '0'),
    :v_campaign_id, CUSTOMER_ID, 'send',
    DATEADD(minute, -ABS(MOD(HASH(CUSTOMER_ID), 1380)) - 60, CURRENT_TIMESTAMP()),
    PREFERRED_CHANNEL, 'mobile'
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID = :P_SEGMENT_ID AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME;

  -- Opens — per-row hash sampling at open_rate
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
    (EVENT_ID, CAMPAIGN_ID, CUSTOMER_ID, EVENT_TYPE, EVENT_TIMESTAMP, CHANNEL, DEVICE_TYPE)
  SELECT
    'S' || LEFT(:v_campaign_id, 7) || 'O' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID), 11, '0'),
    :v_campaign_id, CUSTOMER_ID, 'open',
    DATEADD(minute, -ABS(MOD(HASH(CUSTOMER_ID || 'O'), 1170)) - 30, CURRENT_TIMESTAMP()),
    PREFERRED_CHANNEL, 'mobile'
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID = :P_SEGMENT_ID AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME
    AND ABS(MOD(HASH(CUSTOMER_ID || 'open'), 1000)) < :v_open_rate * 1000;

  -- Clicks — per-row hash sampling at click_rate
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
    (EVENT_ID, CAMPAIGN_ID, CUSTOMER_ID, EVENT_TYPE, EVENT_TIMESTAMP, CHANNEL, DEVICE_TYPE)
  SELECT
    'S' || LEFT(:v_campaign_id, 7) || 'C' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID), 11, '0'),
    :v_campaign_id, CUSTOMER_ID, 'click',
    DATEADD(minute, -ABS(MOD(HASH(CUSTOMER_ID || 'C'), 885)) - 15, CURRENT_TIMESTAMP()),
    PREFERRED_CHANNEL, 'mobile'
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID = :P_SEGMENT_ID AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME
    AND ABS(MOD(HASH(CUSTOMER_ID || 'click'), 1000)) < :v_click_rate * 1000;

  -- Converts — per-row hash sampling at cvr, with revenue
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
    (EVENT_ID, CAMPAIGN_ID, CUSTOMER_ID, EVENT_TYPE, EVENT_TIMESTAMP, CHANNEL, DEVICE_TYPE, REVENUE)
  SELECT
    'S' || LEFT(:v_campaign_id, 7) || 'V' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID), 11, '0'),
    :v_campaign_id, CUSTOMER_ID, 'convert',
    DATEADD(minute, -ABS(MOD(HASH(CUSTOMER_ID || 'V'), 595)) - 5, CURRENT_TIMESTAMP()),
    PREFERRED_CHANNEL, 'mobile',
    ROUND(35.0 + ABS(MOD(HASH(CUSTOMER_ID), 245)), 2)
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID = :P_SEGMENT_ID AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME
    AND ABS(MOD(HASH(CUSTOMER_ID || 'convert'), 1000)) < :v_cvr * 1000;

  v_result := OBJECT_CONSTRUCT(
    'customers_staged', :v_staged_count,
    'segment_id',       :P_SEGMENT_ID,
    'segment_name',     :v_segment_name,
    'campaign_name',    :P_CAMPAIGN_NAME,
    'campaign_id',      :v_campaign_id,
    'status',           'success'
  );
  RETURN :v_result;
END;
$$;

GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.ACTIVATE_SEGMENT(NUMBER, VARCHAR, VARCHAR)
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- SAVE_BRIEF
-- Writer calls this via MCP after authoring a campaign brief.
-- Upserts into CAMPAIGN_BRIEFS; returns the BRIEF_ID.
-- Signature: (P_CAMPAIGN_ID VARCHAR, P_BRIEF_JSON VARIANT)
-- Returns: BRIEF_ID string
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(
  P_CAMPAIGN_ID VARCHAR,
  P_BRIEF_JSON  VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_brief_id VARCHAR;
BEGIN
  -- Generate BRIEF_ID if not provided
  v_brief_id := COALESCE(
    P_BRIEF_JSON:brief_id::VARCHAR,
    'BRF-' || REPLACE(P_CAMPAIGN_ID, 'CMP-', '') || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'HH24MISS')
  );

  -- Upsert brief: structured metadata + full VARIANT content
  MERGE INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS tgt
  USING (SELECT :v_brief_id AS BRIEF_ID) src
  ON (tgt.BRIEF_ID = src.BRIEF_ID)
  WHEN MATCHED THEN UPDATE SET
    CAMPAIGN_ID   = :P_CAMPAIGN_ID,
    STATUS        = COALESCE(:P_BRIEF_JSON:status::VARCHAR, 'draft'),
    CREATED_BY    = :P_BRIEF_JSON:created_by::VARCHAR,
    BRIEF_CONTENT = :P_BRIEF_JSON
  WHEN NOT MATCHED THEN INSERT (
    BRIEF_ID, CAMPAIGN_ID, STATUS, CREATED_BY, CREATED_AT, BRIEF_CONTENT
  ) VALUES (
    :v_brief_id,
    :P_CAMPAIGN_ID,
    COALESCE(:P_BRIEF_JSON:status::VARCHAR, 'draft'),
    :P_BRIEF_JSON:created_by::VARCHAR,
    CURRENT_TIMESTAMP(),
    :P_BRIEF_JSON
  );

  RETURN :v_brief_id;
END;
$$;

GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(VARCHAR, VARIANT)
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- SAVE_CONTENT_ASSET
-- Writer calls this via MCP after generating each content asset.
-- Inserts into CONTENT_ASSETS; returns the ASSET_ID.
-- Signature: (P_BRIEF_ID VARCHAR, P_ASSET_JSON VARIANT)
-- Returns: ASSET_ID string
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(
  P_BRIEF_ID   VARCHAR,
  P_ASSET_JSON VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_asset_id VARCHAR;
BEGIN
  -- Generate ASSET_ID from brief_id + channel + timestamp
  v_asset_id := COALESCE(
    :P_ASSET_JSON:asset_id::VARCHAR,
    'AST-' || REPLACE(:P_BRIEF_ID, 'BRF-', '') || '-' ||
      UPPER(LEFT(:P_ASSET_JSON:channel::VARCHAR, 3)) || '-' ||
      TO_CHAR(CURRENT_TIMESTAMP(), 'HHMMSS')
  );

  -- Use INSERT ... SELECT to allow VARIANT path accessor in column list
  -- (VALUES clause does not support :P_ASSET_JSON:key::TYPE syntax)
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS (
    ASSET_ID, BRIEF_ID, CAMPAIGN_ID, CHANNEL, ASSET_TYPE, CONTENT_BODY,
    HEADLINE, CTA, APPROVAL_STATUS, BRAND_VOICE_SCORE, GENERATED_AT
  )
  SELECT
    :v_asset_id,
    :P_BRIEF_ID,
    :P_ASSET_JSON:campaign_id::VARCHAR,
    :P_ASSET_JSON:channel::VARCHAR,
    :P_ASSET_JSON:asset_type::VARCHAR,
    :P_ASSET_JSON:content_body::VARCHAR,
    :P_ASSET_JSON:headline::VARCHAR,
    :P_ASSET_JSON:cta::VARCHAR,
    COALESCE(:P_ASSET_JSON:approval_status::VARCHAR, 'draft'),
    :P_ASSET_JSON:brand_voice_score::NUMBER,
    CURRENT_TIMESTAMP();

  RETURN :v_asset_id;
END;
$$;

GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(VARCHAR, VARIANT)
  TO ROLE WRITER_MARKETING_ROLE;
