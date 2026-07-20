-- =============================================================================
-- 09_semantic_view.sql  —  Apex Athletics Content Supply Chain
-- Creates: CUSTOMER_360_SV Semantic View
-- 2 base tables: CUSTOMER_360 + MICRO_SEGMENTS joined on RFM/Churn/Channel
-- 18 dimensions, 18 facts, 12 metrics
-- Used by MARKETING_CAMPAIGN_PLANNER agent (CustomerAnalyst tool).
--
-- Key syntax notes (learned from Snowflake docs):
-- • FACTS comes before DIMENSIONS in DDL
-- • dimensionExpression: table_alias.name AS sql_column COMMENT = '...'
-- • RELATIONSHIPS: table_alias (cols) REFERENCES other_alias (cols)
--   (ref cols must be PRIMARY KEY or UNIQUE on the referenced table)
-- • SEMANTIC_VIEW query: ORDER BY uses unqualified column names
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

CREATE OR REPLACE SEMANTIC VIEW WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360_SV
  TABLES (
    c AS WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360
      PRIMARY KEY (CUSTOMER_ID),
    s AS WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS
      PRIMARY KEY (SEGMENT_ID)
      UNIQUE (RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL)
  )
  RELATIONSHIPS (
    c (RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL)
    REFERENCES s (RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL)
  )
  FACTS (
    c.ANNUAL_SPEND             AS ANNUAL_SPEND             COMMENT = 'Annual spend from profile',
    c.TOTAL_SPEND_12M          AS TOTAL_SPEND_12M          COMMENT = 'Total spend last 12 months',
    c.AVG_ORDER_VALUE          AS AVG_ORDER_VALUE          COMMENT = 'Average order value (12 months)',
    c.LOYALTY_POINTS           AS LOYALTY_POINTS           COMMENT = 'Current loyalty points balance',
    c.PURCHASE_COUNT_12M       AS PURCHASE_COUNT_12M       COMMENT = 'Purchases last 12 months',
    c.CART_ADD_COUNT_12M       AS CART_ADD_COUNT_12M       COMMENT = 'Cart adds last 12 months',
    c.TOTAL_EVENTS_12M         AS TOTAL_EVENTS_12M         COMMENT = 'Total behavioral events last 12 months',
    c.ACTIVE_DAYS_12M          AS ACTIVE_DAYS_12M          COMMENT = 'Active days last 12 months',
    c.TRAINING_LOGS_12M        AS TRAINING_LOGS_12M        COMMENT = 'Training logs last 12 months',
    c.EMAIL_OPENS_12M          AS EMAIL_OPENS_12M          COMMENT = 'Emails opened last 12 months',
    c.EMAIL_CLICKS_12M         AS EMAIL_CLICKS_12M         COMMENT = 'Email clicks last 12 months',
    c.CAMPAIGN_CONVERSIONS_12M AS CAMPAIGN_CONVERSIONS_12M COMMENT = 'Campaign conversions last 12 months',
    c.CAMPAIGN_REVENUE_12M     AS CAMPAIGN_REVENUE_12M     COMMENT = 'Campaign revenue last 12 months',
    c.TENURE_DAYS              AS TENURE_DAYS              COMMENT = 'Days since customer signup',
    c.DAYS_SINCE_LAST_PURCHASE AS DAYS_SINCE_LAST_PURCHASE COMMENT = 'Days since last purchase',
    c.LTV_ANNUALIZED           AS LTV_ANNUALIZED           COMMENT = 'Annualized customer lifetime value',
    c.ENGAGEMENT_SCORE         AS ENGAGEMENT_SCORE         COMMENT = 'Engagement score (0-100)',
    s.TOTAL_REVENUE_OPPORTUNITY AS TOTAL_REVENUE_OPPORTUNITY COMMENT = 'Total revenue opportunity for segment'
  )
  DIMENSIONS (
    c.CUSTOMER_ID        AS CUSTOMER_ID        COMMENT = 'Unique customer identifier (CUST-NNNNNN)',
    c.FIRST_NAME         AS FIRST_NAME         COMMENT = 'Customer first name',
    c.LAST_NAME          AS LAST_NAME          COMMENT = 'Customer last name',
    c.EMAIL              AS EMAIL              COMMENT = 'Customer email address',
    c.GENDER             AS GENDER             COMMENT = 'Gender',
    c.CITY               AS CITY               COMMENT = 'City of residence',
    c.STATE              AS STATE              COMMENT = 'US state',
    c.REGION             AS REGION             COMMENT = 'Geographic region',
    c.LOYALTY_TIER_NAME  AS LOYALTY_TIER_NAME  COMMENT = 'Loyalty tier: Starter/Active/Performance/Elite',
    c.PREFERRED_CHANNEL  AS PREFERRED_CHANNEL  COMMENT = 'Preferred channel (email/push/sms)',
    c.TOP_CATEGORY       AS TOP_CATEGORY       COMMENT = 'Top product category (Running/Yoga/Training/etc.)',
    c.MARKETING_OPT_IN   AS MARKETING_OPT_IN   COMMENT = 'Opted in to marketing',
    c.RFM_SEGMENT        AS RFM_SEGMENT        COMMENT = 'RFM segment (Champion/Loyal/Recent/At Risk/Dormant/Potential/Needs Attention/New)',
    c.CHURN_RISK_TIER    AS CHURN_RISK_TIER    COMMENT = 'Churn risk tier (High/Medium/Low)',
    c.SIGNUP_DATE        AS SIGNUP_DATE        COMMENT = 'Date customer joined Apex Athletics',
    c.LAST_PURCHASE_DATE AS LAST_PURCHASE_DATE COMMENT = 'Date of most recent purchase',
    s.SEGMENT_ID         AS SEGMENT_ID         COMMENT = 'Micro-segment ID (1-22)',
    s.SEGMENT_NAME       AS SEGMENT_NAME       COMMENT = 'Full micro-segment name'
  )
  METRICS (
    c.AVG_ENGAGEMENT_SCORE   AS AVG(ENGAGEMENT_SCORE)          COMMENT = 'Average engagement score (0-100)',
    c.AVG_CHURN_RISK         AS AVG(CHURN_RISK_SCORE)          COMMENT = 'Average churn risk score (0-100)',
    c.AVG_HEALTH_SCORE       AS AVG(CUSTOMER_HEALTH_SCORE)     COMMENT = 'Average customer health score',
    c.AVG_LTV                AS AVG(LTV_ANNUALIZED)            COMMENT = 'Average annualized LTV',
    c.TOTAL_LTV              AS SUM(LTV_ANNUALIZED)            COMMENT = 'Total annualized LTV',
    c.TOTAL_REVENUE_OPP      AS SUM(REVENUE_OPPORTUNITY_SCORE) COMMENT = 'Total revenue opportunity',
    c.TOTAL_CAMPAIGN_REVENUE AS SUM(CAMPAIGN_REVENUE_12M)      COMMENT = 'Total campaign revenue last 12 months',
    c.AVG_EMAIL_OPEN_RATE    AS AVG(EMAIL_OPEN_RATE)           COMMENT = 'Average email open rate',
    c.AVG_CLICK_RATE         AS AVG(EMAIL_CLICK_RATE)          COMMENT = 'Average email click-through rate',
    c.AVG_CONVERSION_RATE    AS AVG(CAMPAIGN_CONVERSION_RATE)  COMMENT = 'Average campaign conversion rate',
    c.CUSTOMER_COUNT         AS COUNT(CUSTOMER_ID)             COMMENT = 'Number of distinct customers',
    s.AVG_INTENT_SCORE       AS AVG(INTENT_SCORE)              COMMENT = 'Average segment intent score (60.5-82.9)'
  )
  COMMENT = 'Apex Athletics customer intelligence — CUSTOMER_360 + MICRO_SEGMENTS, 18 dims, 18 facts, 12 metrics';

GRANT SELECT ON VIEW WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360_SV TO ROLE WRITER_MARKETING_ROLE;
