-- =============================================================================
-- 05_campaign_library.sql  —  Apex Athletics Content Supply Chain
-- Creates CAMPAIGN_LIBRARY with 100 AI-generated historical campaigns
-- via CORTEX.COMPLETE — no hard-coded content.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_LIBRARY — 100 historical campaigns with AI-generated content
-- ---------------------------------------------------------------------------
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
