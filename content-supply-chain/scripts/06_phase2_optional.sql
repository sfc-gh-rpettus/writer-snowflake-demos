-- =============================================================================
-- 06_phase2_optional.sql  —  Apex Athletics Content Supply Chain
-- Step 6 of 6 — OPTIONAL
--
-- NOT required for the Phase 1 demo walkthrough.
-- Creates Phase 2 objects for follow-up conversations:
--   • PRODUCT_SENTIMENT_SCORES (CORTEX.SENTIMENT on ~120K gear reviews — slow)
--   • GEO_SEARCH_QUERIES (150 AI-generated AI-search impression rows)
--   • BRAND_VOICE_GUIDELINES (12 brand rules — governance layer)
--   • CHANNEL_TEMPLATES (10 channel format specs)
--
-- Phase 2 demo talking points (if asked):
--   Sentiment: "We run CORTEX.SENTIMENT on every gear review — feeds content tone"
--   GEO:       "GEO_SEARCH_QUERIES tracks Perplexity and ChatGPT brand citations"
--   Brand:     "Every brand rule Writer applies is version-controlled in Snowflake"
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;

CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.PRODUCT_SENTIMENT_SCORES (
  PRODUCT_SENTIMENT_ID   NUMBER AUTOINCREMENT PRIMARY KEY,
  CATEGORY_ID            VARCHAR(10),
  CATEGORY_NAME          VARCHAR(100),
  DEPARTMENT             VARCHAR(50),
  AVG_SENTIMENT          NUMBER(8,4),   -- -1.0 to 1.0
  REVIEW_COUNT           NUMBER(8,0),
  POSITIVE_REVIEW_COUNT  NUMBER(8,0),
  NEUTRAL_REVIEW_COUNT   NUMBER(8,0),
  NEGATIVE_REVIEW_COUNT  NUMBER(8,0),
  TOP_POSITIVE_THEMES    VARCHAR(500),
  TOP_NEGATIVE_THEMES    VARCHAR(500),
  FIT_SCORE              NUMBER(5,2),   -- 0-10 scale
  QUALITY_SCORE          NUMBER(5,2),   -- 0-10 scale
  COMPUTED_AT            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Compute sentiment from gear_review events using CORTEX.SENTIMENT
INSERT INTO WRITER_SNOW_DEMO.MARKETING.PRODUCT_SENTIMENT_SCORES
  (CATEGORY_ID, CATEGORY_NAME, DEPARTMENT, AVG_SENTIMENT, REVIEW_COUNT,
   POSITIVE_REVIEW_COUNT, NEUTRAL_REVIEW_COUNT, NEGATIVE_REVIEW_COUNT,
   TOP_POSITIVE_THEMES, TOP_NEGATIVE_THEMES, FIT_SCORE, QUALITY_SCORE)
SELECT
  pc.CATEGORY_ID,
  pc.CATEGORY_NAME,
  pc.DEPARTMENT,
  AVG(SNOWFLAKE.CORTEX.SENTIMENT(
    e.EVENT_PROPERTIES:review_text::VARCHAR
  ))                                                            AS AVG_SENTIMENT,
  COUNT(*)                                                      AS REVIEW_COUNT,
  COUNT_IF(SNOWFLAKE.CORTEX.SENTIMENT(
    e.EVENT_PROPERTIES:review_text::VARCHAR) > 0.2)            AS POSITIVE_REVIEW_COUNT,
  COUNT_IF(SNOWFLAKE.CORTEX.SENTIMENT(
    e.EVENT_PROPERTIES:review_text::VARCHAR) BETWEEN -0.2 AND 0.2) AS NEUTRAL_REVIEW_COUNT,
  COUNT_IF(SNOWFLAKE.CORTEX.SENTIMENT(
    e.EVENT_PROPERTIES:review_text::VARCHAR) < -0.2)           AS NEGATIVE_REVIEW_COUNT,
  'Good fit, comfortable, durable'                              AS TOP_POSITIVE_THEMES,
  'Sizing inconsistent, limited color options'                  AS TOP_NEGATIVE_THEMES,
  ROUND(UNIFORM(6.0, 9.5, RANDOM()), 1)                        AS FIT_SCORE,
  ROUND(UNIFORM(6.5, 9.5, RANDOM()), 1)                        AS QUALITY_SCORE
FROM WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM e
JOIN WRITER_SNOW_DEMO.MARKETING.PRODUCT_CATEGORIES pc ON pc.CATEGORY_ID = e.CATEGORY_ID
WHERE e.EVENT_TYPE = 'gear_review'
  AND e.EVENT_PROPERTIES:review_text IS NOT NULL
  AND e.EVENT_TIMESTAMP >= DATEADD(year, -1, CURRENT_TIMESTAMP())
GROUP BY pc.CATEGORY_ID, pc.CATEGORY_NAME, pc.DEPARTMENT;

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.PRODUCT_SENTIMENT_SCORES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- GEO_SEARCH_QUERIES — synthetic AI-search impression data
-- Tracks Apex Athletics brand mentions in Perplexity/ChatGPT/Google AI results
-- Phase 2 talking point: dedicated GEO/AEO optimization story
-- Uses CORTEX.COMPLETE to generate realistic AI search queries
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.GEO_SEARCH_QUERIES (
  QUERY_ID             VARCHAR(15)   NOT NULL,
  QUERY_TEXT           VARCHAR(300)  NOT NULL,
  SEARCH_PLATFORM      VARCHAR(20)   NOT NULL,   -- perplexity/chatgpt/google_ai
  CATEGORY             VARCHAR(50),
  IMPRESSIONS          NUMBER(8,0),
  BRAND_MENTIONED      BOOLEAN,
  BRAND_MENTION_RATE   NUMBER(6,4),
  CITATION_URL         VARCHAR(200),
  QUERY_VOLUME         NUMBER(8,0),
  TRACKED_DATE         DATE          NOT NULL
);

-- Generate 150 AI-search query records (3 platforms × 50 queries)
-- Using CORTEX.COMPLETE for realistic query text
INSERT INTO WRITER_SNOW_DEMO.MARKETING.GEO_SEARCH_QUERIES
WITH
  category_seeds AS (
    SELECT * FROM VALUES
      ('Running',    'best running shoes for marathon training', 'CAT-001'),
      ('Running',    'lightweight running shoes women', 'CAT-002'),
      ('Yoga',       'yoga leggings that don''t pill', 'CAT-003'),
      ('Yoga',       'sustainable yoga wear brands', 'CAT-004'),
      ('Training',   'compression gear for recovery athletes', 'CAT-005'),
      ('Training',   'training shoes cross-training', 'CAT-006'),
      ('Outdoor',    'trail running shoes rocky terrain', 'CAT-007'),
      ('Outdoor',    'weather protection running jacket', 'CAT-008'),
      ('Recovery',   'best recovery wear post-workout', 'CAT-009'),
      ('Accessories','high performance sports bras', 'CAT-010')
    AS s(category_name, query_seed, category_id)
  ),
  platforms AS (
    SELECT p.value::VARCHAR AS plt, p.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["perplexity","chatgpt","google_ai"]'))) p
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 150)))
SELECT
  'GEO-' || LPAD(g.n + 1, 5, '0')                              AS QUERY_ID,
  TRIM(SNOWFLAKE.CORTEX.COMPLETE(
    'claude-haiku-4-5',
    'Write a single consumer search query that someone would type into an AI search engine ' ||
    '(Perplexity, ChatGPT) when looking for ' || cs.category_name ||
    ' activewear. Make it natural, 5-12 words. Return ONLY the query text.'
  ))                                                            AS QUERY_TEXT,
  plt.plt                                                       AS SEARCH_PLATFORM,
  cs.category_name                                              AS CATEGORY,
  UNIFORM(500, 25000, RANDOM())                                 AS IMPRESSIONS,
  (MOD(g.n, 4) > 0)                                            AS BRAND_MENTIONED,
  CASE WHEN MOD(g.n, 4) > 0
       THEN ROUND(UNIFORM(0.08, 0.35, RANDOM()), 4)
       ELSE ROUND(UNIFORM(0.01, 0.08, RANDOM()), 4) END        AS BRAND_MENTION_RATE,
  CASE WHEN MOD(g.n, 4) > 0
       THEN 'https://apex-athletics.com/' ||
            LOWER(REPLACE(cs.category_name, ' ', '-')) ||
            '/guides/' || LPAD(MOD(g.n, 20) + 1, 2, '0')
       ELSE NULL END                                           AS CITATION_URL,
  UNIFORM(1000, 100000, RANDOM())                               AS QUERY_VOLUME,
  DATEADD(day, -MOD(g.n, 90), CURRENT_DATE())                  AS TRACKED_DATE
FROM gen g
JOIN category_seeds cs  ON cs.category_id = 'CAT-0' || LPAD(MOD(g.n, 10) + 1, 2, '0')
JOIN platforms      plt ON plt.idx = MOD(g.n, 3);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.GEO_SEARCH_QUERIES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- BRAND_VOICE_GUIDELINES — Apex Athletics tone and style rules
-- Governance/audit layer — "every brand rule Writer applies is in Snowflake"
-- Phase 2 talking point: version-controlled brand governance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.BRAND_VOICE_GUIDELINES (
  GUIDELINE_ID       VARCHAR(10)   NOT NULL,
  CATEGORY           VARCHAR(30)   NOT NULL,   -- tone/style/messaging/prohibited
  RULE_TEXT          VARCHAR(500)  NOT NULL,
  EXAMPLES           VARCHAR(500),
  APPLIES_TO_CHANNEL VARCHAR(100),              -- all / email / social / sms / push
  ACTIVE             BOOLEAN       DEFAULT TRUE,
  CREATED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.BRAND_VOICE_GUIDELINES
  (GUIDELINE_ID, CATEGORY, RULE_TEXT, EXAMPLES, APPLIES_TO_CHANNEL, ACTIVE)
SELECT * FROM VALUES
  ('BGV-001', 'tone',      'Use an active, motivational voice that celebrates athletic achievement without pressure or shame.', 'Good: "You've got this." Bad: "You need to do better."', 'all', TRUE),
  ('BGV-002', 'tone',      'Be authentic and direct — avoid marketing jargon, hyperbole, and empty superlatives.', 'Good: "Engineered for trail runs." Bad: "The most amazing shoes ever!!!"', 'all', TRUE),
  ('BGV-003', 'tone',      'Match tone to segment: Champion = technical/expert, New = welcoming/aspirational, At Risk = empathetic/incentive-led.', NULL, 'email', TRUE),
  ('BGV-004', 'style',     'Subject lines: 35-55 characters, no ALL CAPS, use personalization tokens when available.', '"[First Name], your trail gear is ready" ✓', 'email', TRUE),
  ('BGV-005', 'style',     'CTAs must be action verbs: "Shop", "Explore", "Claim", "Start". Never "Click here" or "Submit".', '"Shop the collection" ✓, "Click here" ✗', 'all', TRUE),
  ('BGV-006', 'style',     'SMS max 160 characters. Include opt-out: "Reply STOP to unsubscribe". No emoji-only messages.', NULL, 'sms', TRUE),
  ('BGV-007', 'messaging', 'Lead with performance benefit, not product features. What can the customer DO with this gear?', '"Run longer, recover faster" vs "Made of 95% polyester"', 'all', TRUE),
  ('BGV-008', 'messaging', 'Use inclusive language — activewear is for everyone regardless of ability, body type, or fitness level.', 'Avoid: "serious athletes only". Use: "for every athlete"', 'all', TRUE),
  ('BGV-009', 'messaging', 'Loyalty tier communications must acknowledge the tier name and specific tier benefits.', '"As an Elite member, you get 48-hour early access..."', 'email', TRUE),
  ('BGV-010', 'prohibited', 'Never use competitor brand names in copy, even in comparisons.', NULL, 'all', TRUE),
  ('BGV-011', 'prohibited', 'Never claim medical benefits or use language that implies health treatment.', '"Helps recovery" ✓, "Treats muscle soreness" ✗', 'all', TRUE),
  ('BGV-012', 'prohibited', 'Do not use urgency language that creates false scarcity (e.g., fake countdown timers).', 'Real inventory signals OK; fabricated "Only 2 left" ✗', 'all', TRUE)
AS g(GUIDELINE_ID, CATEGORY, RULE_TEXT, EXAMPLES, APPLIES_TO_CHANNEL, ACTIVE);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.BRAND_VOICE_GUIDELINES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CHANNEL_TEMPLATES — format constraints per channel
-- Control plane for channel governance
-- Phase 2 talking point: show as a control layer for multi-channel campaigns
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CHANNEL_TEMPLATES (
  TEMPLATE_ID        VARCHAR(10)   NOT NULL,
  CHANNEL            VARCHAR(20)   NOT NULL,
  ASSET_TYPE         VARCHAR(30)   NOT NULL,
  MAX_LENGTH         NUMBER(6,0),
  FORMAT_RULES       VARCHAR(500),
  REQUIRED_ELEMENTS  VARCHAR(300),
  EXAMPLE_CONTENT    VARCHAR(500),
  ACTIVE             BOOLEAN       DEFAULT TRUE
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.CHANNEL_TEMPLATES
  (TEMPLATE_ID, CHANNEL, ASSET_TYPE, MAX_LENGTH, FORMAT_RULES, REQUIRED_ELEMENTS, EXAMPLE_CONTENT, ACTIVE)
SELECT * FROM VALUES
  ('TMP-001', 'email',  'subject_line',    55, 'No ALL CAPS; use personalization [First Name] when available; avoid spam trigger words', 'Compelling hook; 35-55 chars', '"[First Name], your summer gear is here"', TRUE),
  ('TMP-002', 'email',  'email_body',    2000, 'Single column; mobile-first; max 3 CTAs; include unsubscribe footer', 'Headline, 2-3 body paragraphs, primary CTA, image alt text', NULL, TRUE),
  ('TMP-003', 'sms',    'sms_message',    160, 'Plain text only; include STOP opt-out; brand name in first 10 chars', 'Brand name, offer/message, CTA link, STOP opt-out', 'Apex: 25% off your next order. Shop: [link]. Reply STOP to unsubscribe.', TRUE),
  ('TMP-004', 'push',   'push_notification', 90, 'Title max 40 chars; body max 50 chars; include deep link', 'Title, body, action URL', NULL, TRUE),
  ('TMP-005', 'social', 'social_post',    280, 'Platform-specific: IG max 2200 chars, TikTok 2200, LinkedIn 3000', '1-3 hashtags; @mention athletes if applicable; platform tag if required', NULL, TRUE),
  ('TMP-006', 'meta',   'ad_copy',        125, 'Primary text max 125 chars; headline max 27 chars; call-to-action button required', 'Primary text, headline, image/video, CTA button', NULL, TRUE),
  ('TMP-007', 'google', 'ad_copy',         90, 'Headline max 30 chars × 3; description max 90 chars × 2; URL path max 15 chars', '3 headlines, 2 descriptions, final URL', NULL, TRUE),
  ('TMP-008', 'web',    'landing_page',  5000, 'Hero section, features (3-5), social proof, CTA above fold', 'H1 headline, subheadline, feature grid, testimonials, primary CTA', NULL, TRUE),
  ('TMP-009', 'blog',   'blog_post',    10000, 'SEO title max 60 chars; meta description max 155 chars; H1/H2/H3 structure', 'Title, intro, 3-5 H2 sections, conclusion, CTA, meta tags', NULL, TRUE),
  ('TMP-010', 'email',  'influencer_brief', 1500, 'Brand approved talking points only; include required disclosures; no competitor mentions', 'Brand intro, product specs, key messages, hashtags, disclosure requirements', NULL, TRUE)
AS t(TEMPLATE_ID, CHANNEL, ASSET_TYPE, MAX_LENGTH, FORMAT_RULES, REQUIRED_ELEMENTS, EXAMPLE_CONTENT, ACTIVE);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.CHANNEL_TEMPLATES TO ROLE WRITER_MARKETING_ROLE;
