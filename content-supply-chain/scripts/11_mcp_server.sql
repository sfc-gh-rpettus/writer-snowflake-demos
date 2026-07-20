-- =============================================================================
-- 11_mcp_server.sql  —  Apex Athletics Content Supply Chain
-- Creates: MARKETING_MCP_SERVER with 5 tools
-- Tool 1: campaign-planner  — CORTEX_AGENT_RUN (MARKETING_CAMPAIGN_PLANNER)
-- Tool 2: save-brief        — GENERIC (SAVE_BRIEF stored procedure)
-- Tool 3: save-asset        — GENERIC (SAVE_CONTENT_ASSET stored procedure)
-- Tool 4: activate-segment  — GENERIC (ACTIVATE_SEGMENT stored procedure)
-- Tool 5: sql-exec          — SYSTEM_EXECUTE_SQL
--
-- OAuth / Writer Authentication:
-- Writer connects to this MCP server using the WRITER_OAUTH security integration.
-- WRITER_OAUTH is already configured in this account with Writer's OAuth app
-- (redirect URI: https://app.writer.com/mcp/oauth/callback).
-- The GRANT USAGE ON INTEGRATION WRITER_OAUTH is in 00_setup.sql.
-- Writer's team configures the connection using:
--   • Account identifier: <YOUR_SNOWFLAKE_ACCOUNT> (e.g. myorg-myaccount)
--   • MCP endpoint: derived from account URL (see README.md)
--   • Role: WRITER_MARKETING_ROLE
--   • OAuth integration: WRITER_OAUTH (credentials in Writer's app config)
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

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
