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

-- Campaign copy is seeded from a frozen data file rather than generated here.
--
-- These 100 rows were originally produced with ~300 SNOWFLAKE.CORTEX.COMPLETE
-- calls at setup time. That made every run non-deterministic, added unpredictable
-- token spend, and broke when a model name was deprecated. The generated output
-- was captured once and now lives in:
--
--     ../data/campaign_library_seed.sql
--
-- run_all.sh loads it immediately after this script. To load it manually:
--     snow sql -f ../data/campaign_library_seed.sql -c <connection>

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

-- Write-back table: Writer needs SELECT + INSERT + UPDATE
-- UPDATE is required because SAVE_BRIEF upserts via MERGE (WHEN MATCHED THEN UPDATE)
-- and runs EXECUTE AS CALLER, so the caller's role needs the UPDATE privilege.
GRANT SELECT, INSERT, UPDATE ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS TO ROLE WRITER_MARKETING_ROLE;

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
-- Signature: (P_CAMPAIGN_ID VARCHAR, P_BRIEF_JSON VARCHAR)
-- P_BRIEF_JSON is a JSON string — PARSE_JSON() is applied internally.
-- Returns: BRIEF_ID string
--
-- The VARIANT overload is dropped first. Both overloads coexisting is ambiguous
-- for the MCP GENERIC tool, whose identifier carries no signature and whose
-- input_schema declares P_BRIEF_JSON as "string". Older deploys created the
-- VARIANT version, so drop it explicitly rather than relying on CREATE OR REPLACE
-- (which only replaces a matching signature).
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(VARCHAR, VARIANT);

CREATE OR REPLACE PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(
  P_CAMPAIGN_ID VARCHAR,
  P_BRIEF_JSON  VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_brief_id   VARCHAR;
  v_brief_obj  VARIANT;
BEGIN
  v_brief_obj := PARSE_JSON(:P_BRIEF_JSON);

  -- Generate BRIEF_ID if not provided
  v_brief_id := COALESCE(
    v_brief_obj:brief_id::VARCHAR,
    'BRF-' || REPLACE(:P_CAMPAIGN_ID, 'CMP-', '') || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'HH24MISS')
  );

  -- Upsert brief: structured metadata + full VARIANT content
  MERGE INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS tgt
  USING (SELECT :v_brief_id AS BRIEF_ID) src
  ON (tgt.BRIEF_ID = src.BRIEF_ID)
  WHEN MATCHED THEN UPDATE SET
    CAMPAIGN_ID   = :P_CAMPAIGN_ID,
    STATUS        = COALESCE(:v_brief_obj:status::VARCHAR, 'draft'),
    CREATED_BY    = :v_brief_obj:created_by::VARCHAR,
    BRIEF_CONTENT = :v_brief_obj
  WHEN NOT MATCHED THEN INSERT (
    BRIEF_ID, CAMPAIGN_ID, STATUS, CREATED_BY, CREATED_AT, BRIEF_CONTENT
  ) VALUES (
    :v_brief_id,
    :P_CAMPAIGN_ID,
    COALESCE(:v_brief_obj:status::VARCHAR, 'draft'),
    :v_brief_obj:created_by::VARCHAR,
    CURRENT_TIMESTAMP(),
    :v_brief_obj
  );

  RETURN :v_brief_id;
END;
$$;

GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF(VARCHAR, VARCHAR)
  TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- SAVE_CONTENT_ASSET
-- Writer calls this via MCP after generating each content asset.
-- Inserts into CONTENT_ASSETS; returns the ASSET_ID.
-- Signature: (P_BRIEF_ID VARCHAR, P_ASSET_JSON VARCHAR)
-- P_ASSET_JSON is a JSON string — PARSE_JSON() is applied internally.
-- Returns: ASSET_ID string
--
-- The VARIANT overload is dropped first, for the same reason as SAVE_BRIEF:
-- the MCP GENERIC tool identifier carries no signature and input_schema
-- declares P_ASSET_JSON as "string".
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(VARCHAR, VARIANT);

CREATE OR REPLACE PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(
  P_BRIEF_ID   VARCHAR,
  P_ASSET_JSON VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_asset_id  VARCHAR;
  v_asset_obj VARIANT;
BEGIN
  v_asset_obj := PARSE_JSON(:P_ASSET_JSON);

  -- Generate ASSET_ID from brief_id + channel + timestamp
  v_asset_id := COALESCE(
    v_asset_obj:asset_id::VARCHAR,
    'AST-' || REPLACE(:P_BRIEF_ID, 'BRF-', '') || '-' ||
      UPPER(LEFT(v_asset_obj:channel::VARCHAR, 3)) || '-' ||
      TO_CHAR(CURRENT_TIMESTAMP(), 'HHMMSS')
  );

  -- Use INSERT ... SELECT to allow VARIANT path accessor in column list
  -- (VALUES clause does not support :v_asset_obj:key::TYPE syntax)
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CONTENT_ASSETS (
    ASSET_ID, BRIEF_ID, CAMPAIGN_ID, CHANNEL, ASSET_TYPE, CONTENT_BODY,
    HEADLINE, CTA, APPROVAL_STATUS, BRAND_VOICE_SCORE, GENERATED_AT
  )
  SELECT
    :v_asset_id,
    :P_BRIEF_ID,
    :v_asset_obj:campaign_id::VARCHAR,
    :v_asset_obj:channel::VARCHAR,
    :v_asset_obj:asset_type::VARCHAR,
    :v_asset_obj:content_body::VARCHAR,
    :v_asset_obj:headline::VARCHAR,
    :v_asset_obj:cta::VARCHAR,
    COALESCE(:v_asset_obj:approval_status::VARCHAR, 'draft'),
    :v_asset_obj:brand_voice_score::NUMBER,
    CURRENT_TIMESTAMP();

  RETURN :v_asset_id;
END;
$$;

GRANT USAGE ON PROCEDURE WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET(VARCHAR, VARCHAR)
  TO ROLE WRITER_MARKETING_ROLE;
