-- =============================================================================
-- 04_ai_layer.sql  —  Apex Athletics Content Supply Chain
-- Step 4 of 6 — Run time: <3 min
--
-- Creates:
--   • CAMPAIGN_LIBRARY_SEARCH Cortex Search service
--   • CAMPAIGN_BRIEFS_SEARCH Cortex Search service
--   • CUSTOMER_360_SV Semantic View (18 dims, 18 facts, 12 metrics)
--   • MARKETING_CAMPAIGN_PLANNER Cortex Agent (claude-sonnet-4-6)
--   • MARKETING_MCP_SERVER (5 tools: campaign-planner, save-brief,
--                           save-asset, activate-segment, sql-exec)
--
-- Note: Cortex Search services take 1–5 min to index after creation.
--       OAuth auth for MCP: WRITER_OAUTH integration must exist (see 00 header).
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;


-- ──────────────────────────────────────────────────────────────────────────
-- CORTEX SEARCH SERVICES  (from 08_cortex_search.sql)
-- ──────────────────────────────────────────────────────────────────────────
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

-- ──────────────────────────────────────────────────────────────────────────
-- SEMANTIC VIEW  (from 09_semantic_view.sql)
-- ──────────────────────────────────────────────────────────────────────────
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

-- ──────────────────────────────────────────────────────────────────────────
-- CORTEX AGENT  (from 10_cortex_agent.sql)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE AGENT WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGN_PLANNER
  COMMENT = 'Apex Athletics marketing intelligence agent — ranks segments, retrieves campaign history, and supports content supply chain decisions'
  PROFILE = '{"display_name": "Marketing Campaign Planner", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude-sonnet-4-6

  orchestration:
    budget:
      seconds: 60
      tokens: 32000

  instructions:
    response: >
      You are the Apex Athletics Marketing Campaign Planner.
      When answering questions about customers or segments, lead with specific numbers
      (customer counts, LTV, intent scores). When recommending campaigns, cite past
      performance data from the campaign history. Keep responses concise and
      actionable for marketing professionals.
    orchestration: >
      Use CustomerAnalyst for any question about customers, segments, metrics,
      LTV, churn risk, engagement scores, or intent scores.
      Use CampaignSearch for questions about past campaigns, historical performance,
      subject lines, CTAs, open rates, or what has worked for specific segments.
      When asked to rank or prioritize segments, always use CustomerAnalyst first
      for intent scores, then CampaignSearch to provide campaign context.

    sample_questions:
      - question: "What are the top 5 micro-segments by intent score?"
      - question: "How many customers are in the Champion / Low Churn / EMAIL segment?"
      - question: "What past campaigns worked best for at-risk customers?"
      - question: "Compare welcome vs. win-back campaigns by conversion rate"
      - question: "Which segments have the highest cart abandonment rate?"
      - question: "What is the total revenue opportunity if we target all Elite tier segments?"

  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: CustomerAnalyst
        description: >
          Queries the CUSTOMER_360_SV semantic view for customer analytics.
          Use for: segment rankings by intent score, LTV analysis, churn risk,
          engagement scores, campaign conversion rates, customer counts by
          segment/tier/channel, revenue opportunity calculations.

    - tool_spec:
        type: cortex_search
        name: CampaignSearch
        description: >
          Searches the historical campaign library for past campaign performance.
          Use for: finding campaigns by segment type, looking up open/click/conversion
          rates, retrieving subject lines and CTAs, identifying top-performing
          campaign formats for specific audiences.

  tool_resources:
    CustomerAnalyst:
      semantic_view: WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360_SV
      execution_environment:
        type: warehouse
        warehouse: WRITER_WH

    CampaignSearch:
      name: WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY_SEARCH
      max_results: 10
  $$;

GRANT USAGE ON AGENT WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGN_PLANNER
  TO ROLE WRITER_MARKETING_ROLE;

-- ──────────────────────────────────────────────────────────────────────────
-- MCP SERVER  (from 11_mcp_server.sql)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE MCP SERVER WRITER_SNOW_DEMO.MARKETING.MARKETING_MCP_SERVER
  FROM SPECIFICATION $$
    tools:
      - name: "campaign-planner"
        type: "CORTEX_AGENT_RUN"
        identifier: "WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGN_PLANNER"
        title: "Campaign Planner"
        description: >
          Query the Apex Athletics marketing intelligence agent for segment analysis,
          campaign recommendations, and customer intelligence. Use for:
          ranking micro-segments by intent score, LTV analysis, churn risk,
          historical campaign performance, and content strategy recommendations.

      - name: "save-brief"
        type: "GENERIC"
        identifier: "WRITER_SNOW_DEMO.MARKETING.SAVE_BRIEF"
        title: "Save Campaign Brief"
        description: >
          Store a campaign brief that Writer has authored back into Snowflake.
          Writer calls this after generating a brief in its own application.
          Returns the BRIEF_ID for the stored brief.
        config:
          type: "procedure"
          warehouse: "WRITER_WH"
          input_schema:
            type: "object"
            properties:
              P_CAMPAIGN_ID:
                type: "string"
                description: "Campaign ID in CMP-YYYY-NNN format (e.g., CMP-2025-001)"
              P_BRIEF_JSON:
                type: "object"
                description: >
                  Brief content as a JSON object with fields: audience_segment_id,
                  persona_name, objective, target_audience_description, key_messages,
                  tone, channels, primary_kpi, kpi_target, mandatory_inclusions,
                  prohibited_content, brand_voice_notes, created_by
            required: ["P_CAMPAIGN_ID", "P_BRIEF_JSON"]

      - name: "save-asset"
        type: "GENERIC"
        identifier: "WRITER_SNOW_DEMO.MARKETING.SAVE_CONTENT_ASSET"
        title: "Save Content Asset"
        description: >
          Store a single content asset (email, social post, SMS, push notification, etc.)
          that Writer has generated back into Snowflake. Writer calls this for each
          asset it creates. Returns the ASSET_ID for the stored asset.
        config:
          type: "procedure"
          warehouse: "WRITER_WH"
          input_schema:
            type: "object"
            properties:
              P_BRIEF_ID:
                type: "string"
                description: "Brief ID this asset belongs to (returned by save-brief)"
              P_ASSET_JSON:
                type: "object"
                description: >
                  Asset content as a JSON object with fields: campaign_id, channel
                  (email/sms/push/social/web), asset_type (subject_line/email_body/
                  social_post/sms_message/push_notification/landing_page), content_body,
                  headline, cta, approval_status, brand_voice_score
            required: ["P_BRIEF_ID", "P_ASSET_JSON"]

      - name: "activate-segment"
        type: "GENERIC"
        identifier: "WRITER_SNOW_DEMO.MARKETING.ACTIVATE_SEGMENT"
        title: "Activate Segment"
        description: >
          Stage all customers from a micro-segment into the CAMPAIGN_AUDIENCES table
          for Reverse ETL delivery to Braze/SFMC. Idempotent — safe to call multiple
          times. Returns a JSON with customers_staged, segment_name, and status.
        config:
          type: "procedure"
          warehouse: "WRITER_WH"
          input_schema:
            type: "object"
            properties:
              P_SEGMENT_ID:
                type: "number"
                description: "Segment ID from MICRO_SEGMENTS table (1-22)"
              P_CAMPAIGN_NAME:
                type: "string"
                description: "Name of the campaign being activated (e.g., 'Welcome Series Q3')"
              P_CAMPAIGN_CONTENT_ID:
                type: "string"
                description: "Optional: ASSET_ID from CONTENT_ASSETS to link this activation to a specific asset"
            required: ["P_SEGMENT_ID", "P_CAMPAIGN_NAME"]

      - name: "sql-exec"
        type: "SYSTEM_EXECUTE_SQL"
        title: "Execute SQL"
        description: >
          Execute read-only SQL queries against the WRITER_SNOW_DEMO.MARKETING schema.
          Use for ad-hoc analytics: customer lookups, segment queries, campaign
          performance analysis, or any data exploration not covered by campaign-planner.
  $$;

GRANT USAGE ON MCP SERVER WRITER_SNOW_DEMO.MARKETING.MARKETING_MCP_SERVER
  TO ROLE WRITER_MARKETING_ROLE;
