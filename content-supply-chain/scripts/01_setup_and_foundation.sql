-- =============================================================================
-- 01_setup_and_foundation.sql  —  Apex Athletics Content Supply Chain
-- Step 1 of 6 — Run time: <2 min
--
-- Creates: WRITER_SNOW_DEMO database, WRITER_SNOW_DEMO.MARKETING schema,
--          WRITER_WH warehouse, WRITER_MARKETING_ROLE,
--          and all reference tables (12 categories, 4 tiers, 6 campaigns,
--          500 stores, 8 promotions, 6 audience personas)
--
-- Role split (Snowflake best practice):
--   ACCOUNTADMIN — creates roles and sets the role hierarchy
--   SYSADMIN     — creates all objects and grants object-level privileges
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: Role setup (requires ACCOUNTADMIN)
-- CREATE ROLE and GRANT ROLE TO ROLE are account-level operations.
-- SYSADMIN does not have CREATE ROLE by default — this is by design.
-- ─────────────────────────────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;

-- Create the demo role
CREATE ROLE IF NOT EXISTS WRITER_MARKETING_ROLE
  COMMENT = 'Demo role for SE walkthroughs and Writer MCP Server connection';

-- Connect to role hierarchy: SYSADMIN can manage objects owned by this role
-- (Snowflake best practice: all custom roles connect up to SYSADMIN)
GRANT ROLE WRITER_MARKETING_ROLE TO ROLE SYSADMIN;

-- Grant to the SE who will run the demo
-- IMPORTANT: Replace DEMO_USER with your actual Snowflake username
GRANT ROLE WRITER_MARKETING_ROLE TO USER DEMO_USER;

-- OAuth Security Integration — Writer MCP authentication
-- WRITER_OAUTH already exists in this account — this grant is all that is needed.
-- For a fresh account, also uncomment the CREATE SECURITY INTEGRATION block below.
GRANT USAGE ON INTEGRATION WRITER_OAUTH TO ROLE WRITER_MARKETING_ROLE;

-- ── Fresh account only: uncomment to create the OAuth integration ──────────
-- USE ROLE ACCOUNTADMIN;
-- CREATE SECURITY INTEGRATION IF NOT EXISTS WRITER_OAUTH
--   TYPE = OAUTH
--   OAUTH_CLIENT = CUSTOM
--   OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
--   OAUTH_REDIRECT_URI = 'https://app.writer.com/mcp/oauth/callback'
--   OAUTH_ISSUE_REFRESH_TOKENS = TRUE
--   OAUTH_REFRESH_TOKEN_VALIDITY = 7776000
--   -- OAUTH_USE_SECONDARY_ROLES = IMPLICIT  -- uncomment to allow secondary roles
--   ALLOWED_ROLES_LIST = ('WRITER_MARKETING_ROLE')
--   COMMENT = 'OAuth integration for Writer MCP client connection';
-- -- After creation, retrieve the client ID and secret to share with Writer:
-- -- SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WRITER_OAUTH');
-- ──────────────────────────────────────────────────────────────────────────

-- ── Important: set the connecting user's default role and warehouse ─────────
-- The MCP session uses DEFAULT_ROLE — the user must have WRITER_MARKETING_ROLE
-- as their default or they won't have access to the MCP tools.
-- Replace DEMO_USER with the actual Snowflake username connecting via Writer.
-- ALTER USER DEMO_USER SET DEFAULT_ROLE = 'WRITER_MARKETING_ROLE'
--                          DEFAULT_WAREHOUSE = 'WRITER_WH';
-- ──────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: All objects (SYSADMIN)
-- SYSADMIN owns all databases, schemas, tables, and other objects.
-- ─────────────────────────────────────────────────────────────────────────────
USE ROLE SYSADMIN;

-- ──────────────────────────────────────────────────────────────────────────
-- ENVIRONMENT SETUP
-- ──────────────────────────────────────────────────────────────────────────
CREATE WAREHOUSE IF NOT EXISTS WRITER_WH
  WITH WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 300
  AUTO_RESUME  = TRUE
  COMMENT = 'Dedicated warehouse for Apex Athletics Content Supply Chain demo';

USE WAREHOUSE WRITER_WH;

CREATE DATABASE IF NOT EXISTS WRITER_SNOW_DEMO
  COMMENT = 'Apex Athletics Content Supply Chain demo account';

CREATE SCHEMA IF NOT EXISTS WRITER_SNOW_DEMO.MARKETING
  COMMENT = 'Apex Athletics Content Supply Chain demo — all objects live here';

-- Warehouse access
GRANT USAGE   ON WAREHOUSE WRITER_WH TO ROLE WRITER_MARKETING_ROLE;
GRANT OPERATE ON WAREHOUSE WRITER_WH TO ROLE WRITER_MARKETING_ROLE;

-- Database + schema access
GRANT USAGE ON DATABASE WRITER_SNOW_DEMO           TO ROLE WRITER_MARKETING_ROLE;
GRANT USAGE ON SCHEMA   WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- Future-proof grants (auto-grant new tables/views as they are created)
GRANT SELECT ON FUTURE TABLES         IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;
GRANT SELECT ON FUTURE VIEWS          IN SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE WRITER_MARKETING_ROLE;

-- ──────────────────────────────────────────────────────────────────────────
-- REFERENCE TABLES
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.PRODUCT_CATEGORIES (
  CATEGORY_ID   VARCHAR(10)   NOT NULL,
  DEPARTMENT    VARCHAR(50)   NOT NULL,
  CATEGORY_NAME VARCHAR(100)  NOT NULL,
  MIN_PRICE     NUMBER(8,2)   NOT NULL,
  MAX_PRICE     NUMBER(8,2)   NOT NULL
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.PRODUCT_CATEGORIES
SELECT * FROM VALUES
  ('CAT-001', 'Running',     'Performance Running Shoes',  89.00, 220.00),
  ('CAT-002', 'Running',     'Running Apparel',            45.00, 120.00),
  ('CAT-003', 'Yoga',        'Yoga Pants & Leggings',      55.00, 130.00),
  ('CAT-004', 'Yoga',        'Yoga Tops & Bras',           35.00,  85.00),
  ('CAT-005', 'Training',    'Compression Gear',           40.00, 110.00),
  ('CAT-006', 'Training',    'Training Shoes',             80.00, 180.00),
  ('CAT-007', 'Outdoor',     'Trail Running',              95.00, 250.00),
  ('CAT-008', 'Outdoor',     'Weather Protection',         60.00, 200.00),
  ('CAT-009', 'Recovery',    'Recovery Wear',              50.00, 150.00),
  ('CAT-010', 'Accessories', 'Sports Bras',                35.00,  75.00),
  ('CAT-011', 'Accessories', 'Socks & Gear',               12.00,  45.00),
  ('CAT-012', 'Lifestyle',   'Athleisure',                 40.00, 120.00)
AS c(CATEGORY_ID, DEPARTMENT, CATEGORY_NAME, MIN_PRICE, MAX_PRICE);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.PRODUCT_CATEGORIES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- LOYALTY_TIERS — Starter / Active / Performance / Elite
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.LOYALTY_TIERS (
  TIER_ID            VARCHAR(10)   NOT NULL,
  TIER_NAME          VARCHAR(30)   NOT NULL,
  MIN_ANNUAL_SPEND   NUMBER(8,2)   NOT NULL,
  MAX_ANNUAL_SPEND   NUMBER(8,2)   NOT NULL,
  POINTS_MULTIPLIER  NUMBER(4,2)   NOT NULL,
  DISCOUNT_PCT       NUMBER(4,1)   NOT NULL
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.LOYALTY_TIERS
SELECT * FROM VALUES
  ('TIER-001', 'Starter',      0,      299,   1.0,   0),
  ('TIER-002', 'Active',       300,    999,   1.25,  5),
  ('TIER-003', 'Performance',  1000,   2499,  1.5,  10),
  ('TIER-004', 'Elite',        2500,  99999,  2.0,  15)
AS t(TIER_ID, TIER_NAME, MIN_ANNUAL_SPEND, MAX_ANNUAL_SPEND, POINTS_MULTIPLIER, DISCOUNT_PCT);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.LOYALTY_TIERS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- MARKETING_CAMPAIGNS — 6 campaign types (dates shift to current year)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGNS (
  CAMPAIGN_ID       VARCHAR(15)   NOT NULL,
  CAMPAIGN_NAME     VARCHAR(50)   NOT NULL,
  CAMPAIGN_TYPE     VARCHAR(30)   NOT NULL,
  START_DATE        DATE,
  END_DATE          DATE,
  CHANNELS          VARCHAR(100),
  MESSAGE           VARCHAR(200),
  RESPONSE_RATE     NUMBER(5,2),
  CONVERSION_RATE   NUMBER(5,2)
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGNS
SELECT
  CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE,
  DATEADD(year, YEAR(CURRENT_DATE()) - 2025, START_DATE::DATE) AS START_DATE,
  DATEADD(year, YEAR(CURRENT_DATE()) - 2025, END_DATE::DATE)   AS END_DATE,
  CHANNELS, MESSAGE, RESPONSE_RATE, CONVERSION_RATE
FROM (
  SELECT * FROM VALUES
    ('CMP-2025-001', 'Welcome_Series',     'Welcome',        '2025-01-01', '2025-12-31', 'Email,Push,SMS',    'Welcome to Apex Athletics!',                  0.45, 0.20),
    ('CMP-2025-006', 'Win_Back_Dormant',   'Re-engagement',  '2025-01-01', '2025-12-31', 'Email,Retargeting', 'We miss your energy! 25% off',                0.12, 0.08),
    ('CMP-2025-016', 'Marathon_Season',    'Seasonal',       '2025-03-01', '2025-05-31', 'Email,Social,Web',  'Race day is coming. Are you ready?',          0.28, 0.12),
    ('CMP-2025-026', 'New_Trail_Shoes',    'Product Launch', '2025-04-01', '2025-04-30', 'Social,Email,Web',  'Introducing the TrailBlazer X1',              0.35, 0.15),
    ('CMP-2025-061', 'Elite_Early_Access', 'Loyalty',        '2025-01-01', '2025-12-31', 'Email,App',         'Exclusive drop: 48hr early access',           0.52, 0.30),
    ('CMP-2025-081', 'Cart_Recovery',      'Cart Abandon',   '2025-01-01', '2025-12-31', 'Email,Push',        'Still thinking about it? Its selling fast',   0.22, 0.18)
  AS c(CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE, START_DATE, END_DATE, CHANNELS, MESSAGE, RESPONSE_RATE, CONVERSION_RATE)
);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.MARKETING_CAMPAIGNS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- STORES — 500 retail store locations
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.STORES (
  STORE_ID      VARCHAR(10)   NOT NULL,
  STORE_NAME    VARCHAR(100)  NOT NULL,
  STORE_TYPE    VARCHAR(20)   NOT NULL,  -- Flagship / Standard / Outlet / Express
  CITY          VARCHAR(50)   NOT NULL,
  STATE         VARCHAR(2)    NOT NULL,
  ZIP_CODE      VARCHAR(10),
  REGION        VARCHAR(20)   NOT NULL,
  OPENED_DATE   DATE
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.STORES
SELECT
  'STR-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 3, '0')  AS STORE_ID,
  'Apex Athletics ' || CITY || ' ' || STORE_TYPE                AS STORE_NAME,
  STORE_TYPE,
  CITY,
  STATE,
  ZIP_CODE,
  REGION,
  DATEADD(day, -UNIFORM(30, 3650, RANDOM()), CURRENT_DATE())    AS OPENED_DATE
FROM (
  SELECT
    s.value:city::VARCHAR    AS CITY,
    s.value:state::VARCHAR   AS STATE,
    s.value:zip::VARCHAR     AS ZIP_CODE,
    s.value:region::VARCHAR  AS REGION,
    t.value::VARCHAR         AS STORE_TYPE
  FROM (
    SELECT PARSE_JSON('[
      {"city":"New York","state":"NY","zip":"10001","region":"Northeast"},
      {"city":"Los Angeles","state":"CA","zip":"90001","region":"West"},
      {"city":"Chicago","state":"IL","zip":"60601","region":"Midwest"},
      {"city":"Houston","state":"TX","zip":"77001","region":"South"},
      {"city":"Phoenix","state":"AZ","zip":"85001","region":"Southwest"},
      {"city":"Philadelphia","state":"PA","zip":"19101","region":"Northeast"},
      {"city":"San Antonio","state":"TX","zip":"78201","region":"South"},
      {"city":"San Diego","state":"CA","zip":"92101","region":"West"},
      {"city":"Dallas","state":"TX","zip":"75201","region":"South"},
      {"city":"San Jose","state":"CA","zip":"95101","region":"West"},
      {"city":"Austin","state":"TX","zip":"78701","region":"South"},
      {"city":"Jacksonville","state":"FL","zip":"32099","region":"South"},
      {"city":"Fort Worth","state":"TX","zip":"76101","region":"South"},
      {"city":"Columbus","state":"OH","zip":"43085","region":"Midwest"},
      {"city":"Charlotte","state":"NC","zip":"28201","region":"Southeast"},
      {"city":"San Francisco","state":"CA","zip":"94101","region":"West"},
      {"city":"Indianapolis","state":"IN","zip":"46201","region":"Midwest"},
      {"city":"Seattle","state":"WA","zip":"98101","region":"Northwest"},
      {"city":"Denver","state":"CO","zip":"80201","region":"Mountain"},
      {"city":"Nashville","state":"TN","zip":"37201","region":"South"},
      {"city":"Oklahoma City","state":"OK","zip":"73101","region":"South"},
      {"city":"El Paso","state":"TX","zip":"79901","region":"Southwest"},
      {"city":"Washington","state":"DC","zip":"20001","region":"Northeast"},
      {"city":"Las Vegas","state":"NV","zip":"89101","region":"Southwest"},
      {"city":"Louisville","state":"KY","zip":"40201","region":"Midwest"}
    ]') AS cities
  ), LATERAL FLATTEN(INPUT => cities) s,
  LATERAL FLATTEN(INPUT => PARSE_JSON('["Flagship","Standard","Outlet","Express","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard","Standard"]')) t
) src
LIMIT 500;

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.STORES TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- PROMOTIONS — 8 date-shifted promotional offers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.PROMOTIONS (
  PROMO_ID         VARCHAR(10)   NOT NULL,
  PROMO_CODE       VARCHAR(20)   NOT NULL,
  PROMO_NAME       VARCHAR(100)  NOT NULL,
  DISCOUNT_TYPE    VARCHAR(20)   NOT NULL,  -- pct / fixed / free_shipping
  DISCOUNT_VALUE   NUMBER(6,2)   NOT NULL,
  MIN_ORDER_VALUE  NUMBER(8,2),
  START_DATE       DATE          NOT NULL,
  END_DATE         DATE          NOT NULL,
  APPLICABLE_TIERS VARCHAR(100)
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.PROMOTIONS
SELECT
  PROMO_ID, PROMO_CODE, PROMO_NAME, DISCOUNT_TYPE, DISCOUNT_VALUE,
  MIN_ORDER_VALUE,
  DATEADD(year, YEAR(CURRENT_DATE()) - 2025, START_DATE::DATE) AS START_DATE,
  DATEADD(year, YEAR(CURRENT_DATE()) - 2025, END_DATE::DATE)   AS END_DATE,
  APPLICABLE_TIERS
FROM (
  SELECT * FROM VALUES
    ('PRM-001', 'WELCOME10',    'New Member Welcome',       'pct',          10.0, NULL,   '2025-01-01', '2025-12-31', 'Starter,Active'),
    ('PRM-002', 'ELITE15',      'Elite Member Discount',    'pct',          15.0, 50.00,  '2025-01-01', '2025-12-31', 'Elite'),
    ('PRM-003', 'MARATHON25',   'Marathon Season Special',  'pct',          25.0, 75.00,  '2025-03-01', '2025-05-31', 'All'),
    ('PRM-004', 'TRAILX1EARLY', 'TrailBlazer X1 Early',    'pct',          20.0, 100.00, '2025-04-01', '2025-04-07', 'Performance,Elite'),
    ('PRM-005', 'WINBACK25',    'Win-Back 25% Off',         'pct',          25.0, 40.00,  '2025-01-01', '2025-12-31', 'All'),
    ('PRM-006', 'CARTSHIP',     'Free Shipping Cart Save',  'free_shipping',  0.0, 60.00,  '2025-01-01', '2025-12-31', 'All'),
    ('PRM-007', 'NEWYEAR20',    'New Year Fitness 20',      'pct',          20.0, NULL,   '2025-01-01', '2025-01-31', 'All'),
    ('PRM-008', 'HOLIDAY30',    'Holiday Gifting 30',       'pct',          30.0, 80.00,  '2025-11-01', '2025-12-31', 'All')
  AS p(PROMO_ID, PROMO_CODE, PROMO_NAME, DISCOUNT_TYPE, DISCOUNT_VALUE, MIN_ORDER_VALUE,
       START_DATE, END_DATE, APPLICABLE_TIERS)
);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.PROMOTIONS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- AUDIENCE_SEGMENTS — 6 marketer-friendly personas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.AUDIENCE_SEGMENTS (
  PERSONA_ID                VARCHAR(10)   NOT NULL,
  PERSONA_NAME              VARCHAR(100)  NOT NULL,
  DESCRIPTION               VARCHAR(500)  NOT NULL,
  PRIMARY_SPORT             VARCHAR(50)   NOT NULL,
  AGE_RANGE                 VARCHAR(20)   NOT NULL,
  PRICE_SENSITIVITY         VARCHAR(20)   NOT NULL,
  CHANNEL_PREFERENCE        VARCHAR(50)   NOT NULL,
  MOTIVATIONS               VARCHAR(300)  NOT NULL,
  MICRO_SEGMENT_IDS         ARRAY,
  TOTAL_CUSTOMERS           NUMBER(8,0),
  AVG_LTV                   NUMBER(10,2)
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.AUDIENCE_SEGMENTS
SELECT
  PERSONA_ID, PERSONA_NAME, DESCRIPTION, PRIMARY_SPORT, AGE_RANGE,
  PRICE_SENSITIVITY, CHANNEL_PREFERENCE, MOTIVATIONS,
  PARSE_JSON(MICRO_SEGMENT_IDS)::ARRAY AS MICRO_SEGMENT_IDS,
  TOTAL_CUSTOMERS, AVG_LTV
FROM (
  SELECT * FROM VALUES
    ('AUD-001', 'The Competitive Runner',
     'High-performance runners training for races. Data-driven, gear-obsessed, early adopters of new running tech.',
     'Running', '28-42', 'Low', 'Email,App',
     'Performance improvement, race PRs, latest gear technology, community recognition',
     '[1,2,3]', 8200, 1450.00),
    ('AUD-002', 'The Weekend Warrior',
     'Active adults who exercise regularly but not competitively. Value quality, comfort, and versatility.',
     'Training', '32-50', 'Medium', 'Email,Social',
     'Work-life balance, feeling fit, social exercise, practical gear that performs',
     '[4,5,6]', 12400, 820.00),
    ('AUD-003', 'The Yoga Enthusiast',
     'Dedicated practitioners, from studio regulars to home practice. Value sustainability, fit, and fabric quality.',
     'Yoga', '25-45', 'Medium', 'Social,Email',
     'Mindfulness, community, sustainable fashion, functional beauty, body positivity',
     '[7,8,9]', 9600, 690.00),
    ('AUD-004', 'The Trail Seeker',
     'Outdoor adventurers who run, hike, and explore. Premium gear buyers who prioritize durability.',
     'Outdoor', '30-48', 'Low', 'Email,App',
     'Adventure, durability, technical performance, environmental connection, gear that lasts',
     '[10,11,12]', 5800, 1820.00),
    ('AUD-005', 'The Lifestyle Athlete',
     'Fashion-forward customers who wear activewear socially. Trend-driven, community-influenced buyers.',
     'Lifestyle', '22-38', 'High', 'Social,Push',
     'Style, community validation, social currency, brand identity, athleisure as lifestyle',
     '[13,14,15]', 11200, 540.00),
    ('AUD-006', 'The Recovery-Focused',
     'Athletes prioritizing recovery as part of performance. Interested in compression, sleep gear, and wellness.',
     'Recovery', '35-55', 'Medium', 'Email,App',
     'Longevity, performance maintenance, injury prevention, holistic wellness approach',
     '[16,17,18]', 3000, 1100.00)
  AS a(PERSONA_ID, PERSONA_NAME, DESCRIPTION, PRIMARY_SPORT, AGE_RANGE,
       PRICE_SENSITIVITY, CHANNEL_PREFERENCE, MOTIVATIONS, MICRO_SEGMENT_IDS,
       TOTAL_CUSTOMERS, AVG_LTV)
);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.AUDIENCE_SEGMENTS TO ROLE WRITER_MARKETING_ROLE;
