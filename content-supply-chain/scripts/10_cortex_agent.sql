-- =============================================================================
-- 10_cortex_agent.sql  —  Apex Athletics Content Supply Chain
-- Creates: MARKETING_CAMPAIGN_PLANNER Cortex Agent
-- Tools: CustomerAnalyst (Semantic View → Cortex Analyst)
--        CampaignSearch (CAMPAIGN_LIBRARY_SEARCH + CAMPAIGN_BRIEFS_SEARCH)
-- Model: claude-sonnet-4-6
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

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
