-- =============================================================================
-- 07_stored_procedures.sql  —  Apex Athletics Content Supply Chain
-- Creates: ACTIVATE_SEGMENT, SAVE_BRIEF, SAVE_CONTENT_ASSET
-- All three are exposed as MCP tools via MARKETING_MCP_SERVER.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- ACTIVATE_SEGMENT
-- Stages all customers from a micro-segment into CAMPAIGN_AUDIENCES.
-- Idempotent: skips customers already staged for the same campaign.
-- Called by Writer via MCP after generating campaign content.
-- Signature: (P_SEGMENT_ID NUMBER, P_CAMPAIGN_NAME VARCHAR, P_CAMPAIGN_CONTENT_ID VARCHAR DEFAULT NULL)
-- Returns JSON: {"customers_staged": N, "segment_name": "...", "status": "success"}
-- ---------------------------------------------------------------------------
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
BEGIN
  -- Look up segment name
  SELECT SEGMENT_NAME INTO :v_segment_name
  FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS
  WHERE SEGMENT_ID = :P_SEGMENT_ID;

  -- Insert customers from the segment, skipping existing pending records for same campaign
  INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
    (SEGMENT_ID, SEGMENT_NAME, CUSTOMER_ID, EMAIL, FIRST_NAME, PREFERRED_CHANNEL,
     CAMPAIGN_NAME, CAMPAIGN_CONTENT_ID, PRIORITY_RANK, STATUS, CREATED_AT)
  SELECT
    :P_SEGMENT_ID,
    :v_segment_name,
    c.CUSTOMER_ID,
    c.EMAIL,
    c.FIRST_NAME,
    c.PREFERRED_CHANNEL,
    :P_CAMPAIGN_NAME,
    :P_CAMPAIGN_CONTENT_ID,
    ROW_NUMBER() OVER (ORDER BY c360.CUSTOMER_HEALTH_SCORE DESC),
    'pending',
    CURRENT_TIMESTAMP()
  FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360 c360
  JOIN WRITER_SNOW_DEMO.MARKETING.CUSTOMERS c ON c.CUSTOMER_ID = c360.CUSTOMER_ID
  WHERE c360.RFM_SEGMENT     = (SELECT RFM_SEGMENT     FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND c360.CHURN_RISK_TIER = (SELECT CHURN_RISK_TIER FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND c360.PREFERRED_CHANNEL = (SELECT PREFERRED_CHANNEL FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS WHERE SEGMENT_ID = :P_SEGMENT_ID)
    AND NOT EXISTS (
      SELECT 1 FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES ca
      WHERE ca.CUSTOMER_ID = c.CUSTOMER_ID
        AND ca.CAMPAIGN_NAME = :P_CAMPAIGN_NAME
        AND ca.STATUS = 'pending'
    );

  -- Count how many were staged
  SELECT COUNT(*) INTO :v_staged_count
  FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_AUDIENCES
  WHERE SEGMENT_ID    = :P_SEGMENT_ID
    AND CAMPAIGN_NAME = :P_CAMPAIGN_NAME
    AND STATUS        = 'pending';

  -- Build and return result JSON
  v_result := OBJECT_CONSTRUCT(
    'customers_staged', :v_staged_count,
    'segment_id',       :P_SEGMENT_ID,
    'segment_name',     :v_segment_name,
    'campaign_name',    :P_CAMPAIGN_NAME,
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

  -- Upsert brief
  MERGE INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_BRIEFS tgt
  USING (SELECT :v_brief_id AS BRIEF_ID) src
  ON (tgt.BRIEF_ID = src.BRIEF_ID)
  WHEN MATCHED THEN UPDATE SET
    CAMPAIGN_ID                 = :P_CAMPAIGN_ID,
    AUDIENCE_SEGMENT_ID         = :P_BRIEF_JSON:audience_segment_id::VARCHAR,
    PERSONA_NAME                = :P_BRIEF_JSON:persona_name::VARCHAR,
    OBJECTIVE                   = :P_BRIEF_JSON:objective::VARCHAR,
    TARGET_AUDIENCE_DESCRIPTION = :P_BRIEF_JSON:target_audience_description::VARCHAR,
    KEY_MESSAGES                = :P_BRIEF_JSON:key_messages::ARRAY,
    TONE                        = :P_BRIEF_JSON:tone::VARCHAR,
    CHANNELS                    = :P_BRIEF_JSON:channels::ARRAY,
    PRIMARY_KPI                 = :P_BRIEF_JSON:primary_kpi::VARCHAR,
    KPI_TARGET                  = :P_BRIEF_JSON:kpi_target::VARCHAR,
    MANDATORY_INCLUSIONS        = :P_BRIEF_JSON:mandatory_inclusions::VARCHAR,
    PROHIBITED_CONTENT          = :P_BRIEF_JSON:prohibited_content::VARCHAR,
    PRODUCT_FOCUS               = :P_BRIEF_JSON:product_focus::VARCHAR,
    INSPIRATION_CAMPAIGN_IDS    = :P_BRIEF_JSON:inspiration_campaign_ids::ARRAY,
    BRAND_VOICE_NOTES           = :P_BRIEF_JSON:brand_voice_notes::VARCHAR,
    STATUS                      = COALESCE(:P_BRIEF_JSON:status::VARCHAR, 'draft'),
    CREATED_BY                  = :P_BRIEF_JSON:created_by::VARCHAR
  WHEN NOT MATCHED THEN INSERT (
    BRIEF_ID, CAMPAIGN_ID, AUDIENCE_SEGMENT_ID, PERSONA_NAME, OBJECTIVE,
    TARGET_AUDIENCE_DESCRIPTION, KEY_MESSAGES, TONE, CHANNELS, PRIMARY_KPI,
    KPI_TARGET, MANDATORY_INCLUSIONS, PROHIBITED_CONTENT, PRODUCT_FOCUS,
    INSPIRATION_CAMPAIGN_IDS, BRAND_VOICE_NOTES, STATUS, CREATED_BY, CREATED_AT
  ) VALUES (
    :v_brief_id, :P_CAMPAIGN_ID,
    :P_BRIEF_JSON:audience_segment_id::VARCHAR,
    :P_BRIEF_JSON:persona_name::VARCHAR,
    :P_BRIEF_JSON:objective::VARCHAR,
    :P_BRIEF_JSON:target_audience_description::VARCHAR,
    :P_BRIEF_JSON:key_messages::ARRAY,
    :P_BRIEF_JSON:tone::VARCHAR,
    :P_BRIEF_JSON:channels::ARRAY,
    :P_BRIEF_JSON:primary_kpi::VARCHAR,
    :P_BRIEF_JSON:kpi_target::VARCHAR,
    :P_BRIEF_JSON:mandatory_inclusions::VARCHAR,
    :P_BRIEF_JSON:prohibited_content::VARCHAR,
    :P_BRIEF_JSON:product_focus::VARCHAR,
    :P_BRIEF_JSON:inspiration_campaign_ids::ARRAY,
    :P_BRIEF_JSON:brand_voice_notes::VARCHAR,
    COALESCE(:P_BRIEF_JSON:status::VARCHAR, 'draft'),
    :P_BRIEF_JSON:created_by::VARCHAR,
    CURRENT_TIMESTAMP()
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
