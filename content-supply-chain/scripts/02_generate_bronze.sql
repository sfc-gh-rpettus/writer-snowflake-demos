-- =============================================================================
-- 02_generate_bronze.sql  —  Apex Athletics Content Supply Chain
-- Generates: CUSTOMERS (50K), EVENT_STREAM (~2M), CAMPAIGN_EVENTS (156K)
-- Pure SQL using TABLE(GENERATOR(ROWCOUNT => N)) — no Python required.
--
-- Customer cohort design (MOD(g.n, 10)):
--   Cohorts 0-6, 9: Normal active customers (purchases 0-181 days ago)
--   Cohort 7 (at-risk): Purchases 181-365 days ago → High churn, high frequency
--   Cohort 8 (dormant): Purchases 366-730 days ago → outside 12m window → null purchase metrics
-- This produces all 8 RFM segments needed for MICRO_SEGMENTS.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE WRITER_WH;
USE SCHEMA WRITER_SNOW_DEMO.MARKETING;

-- ---------------------------------------------------------------------------
-- CUSTOMERS — 50,000 rows
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CUSTOMERS (
  CUSTOMER_ID          VARCHAR(12)   NOT NULL,
  FIRST_NAME           VARCHAR(50)   NOT NULL,
  LAST_NAME            VARCHAR(50)   NOT NULL,
  EMAIL                VARCHAR(100)  NOT NULL,
  PHONE                VARCHAR(20),
  DATE_OF_BIRTH        DATE,
  GENDER               VARCHAR(20),
  CITY                 VARCHAR(50),
  STATE                VARCHAR(2),
  ZIP_CODE             VARCHAR(10),
  REGION               VARCHAR(20),
  LOYALTY_TIER_ID      VARCHAR(10),
  LOYALTY_TIER_NAME    VARCHAR(30),
  ANNUAL_SPEND         NUMBER(10,2),
  LOYALTY_POINTS       NUMBER(10,0),
  PREFERRED_CHANNEL    VARCHAR(20),
  TOP_CATEGORY         VARCHAR(50),
  MARKETING_OPT_IN     BOOLEAN,
  PUSH_OPT_IN          BOOLEAN,
  SMS_OPT_IN           BOOLEAN,
  NEAREST_STORE_ID     VARCHAR(10),
  SIGNUP_DATE          DATE,
  LAST_LOGIN_DATE      DATE
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.CUSTOMERS
WITH
  first_names AS (
    SELECT f.value::VARCHAR AS fname, f.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["James","John","Robert","Michael","William","David","Richard","Joseph","Thomas","Charles","Mary","Patricia","Jennifer","Linda","Barbara","Elizabeth","Susan","Jessica","Sarah","Karen","Emma","Olivia","Ava","Isabella","Sophia","Mia","Charlotte","Amelia","Harper","Evelyn","Liam","Noah","Oliver","Elijah","Lucas","Mason","Logan","Ethan","Aiden","Jackson","Aria","Luna","Chloe","Penelope","Layla","Riley","Zoey","Nora","Lily","Eleanor","Ryan","Daniel","Tyler","Nathan","Blake","Cameron","Jordan","Morgan","Casey","Taylor"]'))) f
  ),
  last_names AS (
    SELECT l.value::VARCHAR AS lname, l.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson","Anderson","Thomas","Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White","Harris","Sanchez","Clark","Ramirez","Lewis","Robinson","Walker","Young","Allen","King","Wright","Scott","Torres","Nguyen","Hill","Flores","Green","Adams","Nelson","Baker","Hall","Rivera","Campbell","Mitchell","Carter","Roberts"]'))) l
  ),
  categories AS (
    SELECT c.value::VARCHAR AS cat_name, c.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["Running","Yoga","Training","Outdoor","Recovery","Accessories","Lifestyle","Running","Training","Yoga","Running","Outdoor"]'))) c
  ),
  states_data AS (
    SELECT s.value:state::VARCHAR AS state_code,
           s.value:city::VARCHAR  AS city_name,
           s.value:region::VARCHAR AS region_name,
           s.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('[
      {"state":"NY","city":"New York","region":"Northeast"},{"state":"CA","city":"Los Angeles","region":"West"},
      {"state":"TX","city":"Houston","region":"South"},{"state":"FL","city":"Miami","region":"South"},
      {"state":"IL","city":"Chicago","region":"Midwest"},{"state":"PA","city":"Philadelphia","region":"Northeast"},
      {"state":"AZ","city":"Phoenix","region":"Southwest"},{"state":"WA","city":"Seattle","region":"Northwest"},
      {"state":"CO","city":"Denver","region":"Mountain"},{"state":"GA","city":"Atlanta","region":"Southeast"},
      {"state":"NC","city":"Charlotte","region":"Southeast"},{"state":"OH","city":"Columbus","region":"Midwest"},
      {"state":"TN","city":"Nashville","region":"South"},{"state":"OR","city":"Portland","region":"Northwest"},
      {"state":"MA","city":"Boston","region":"Northeast"},{"state":"MN","city":"Minneapolis","region":"Midwest"},
      {"state":"MO","city":"St. Louis","region":"Midwest"},{"state":"WI","city":"Milwaukee","region":"Midwest"},
      {"state":"NV","city":"Las Vegas","region":"Southwest"},{"state":"UT","city":"Salt Lake City","region":"Mountain"}
    ]'))) s
  ),
  gen AS (
    SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 50000))
  )
SELECT
  'CUST-' || LPAD(g.n + 1, 6, '0')                              AS CUSTOMER_ID,
  fn.fname                                                        AS FIRST_NAME,
  ln.lname                                                        AS LAST_NAME,
  LOWER(fn.fname) || '.' || LOWER(ln.lname) || (g.n + 1)::VARCHAR || '@example.com' AS EMAIL,
  '(' || (200 + MOD(g.n, 800)) || ') ' || LPAD(MOD(g.n * 7, 10000), 4, '0') || '-' || LPAD(MOD(g.n * 13, 10000), 4, '0') AS PHONE,
  DATEADD(day, -UNIFORM(6570, 18250, RANDOM()), CURRENT_DATE())  AS DATE_OF_BIRTH,
  CASE MOD(g.n, 3) WHEN 0 THEN 'Female' WHEN 1 THEN 'Male' ELSE 'Non-binary' END AS GENDER,
  sd.city_name                                                    AS CITY,
  sd.state_code                                                   AS STATE,
  LPAD(MOD(g.n * 17 + 10000, 90000) + 10000, 5, '0')            AS ZIP_CODE,
  sd.region_name                                                  AS REGION,
  CASE
    WHEN MOD(g.n, 10) < 5 THEN 'TIER-001'
    WHEN MOD(g.n, 10) < 8 THEN 'TIER-002'
    WHEN MOD(g.n, 10) < 9 THEN 'TIER-003'
    ELSE 'TIER-004'
  END                                                             AS LOYALTY_TIER_ID,
  CASE
    WHEN MOD(g.n, 10) < 5 THEN 'Starter'
    WHEN MOD(g.n, 10) < 8 THEN 'Active'
    WHEN MOD(g.n, 10) < 9 THEN 'Performance'
    ELSE 'Elite'
  END                                                             AS LOYALTY_TIER_NAME,
  CASE
    WHEN MOD(g.n, 10) < 5 THEN ROUND(UNIFORM(10,  299, RANDOM()), 2)
    WHEN MOD(g.n, 10) < 8 THEN ROUND(UNIFORM(300, 999, RANDOM()), 2)
    WHEN MOD(g.n, 10) < 9 THEN ROUND(UNIFORM(1000,2499, RANDOM()), 2)
    ELSE                        ROUND(UNIFORM(2500,8000, RANDOM()), 2)
  END                                                             AS ANNUAL_SPEND,
  UNIFORM(0, 15000, RANDOM())                                     AS LOYALTY_POINTS,
  -- Balanced 3-way channel split using MOD(n,3) to avoid cohort-channel correlation
  CASE MOD(g.n, 3) WHEN 0 THEN 'email' WHEN 1 THEN 'push' ELSE 'sms' END AS PREFERRED_CHANNEL,
  CASE MOD(g.n, 12)
    WHEN 0 THEN 'Running' WHEN 1 THEN 'Yoga' WHEN 2 THEN 'Training' WHEN 3 THEN 'Outdoor'
    WHEN 4 THEN 'Recovery' WHEN 5 THEN 'Accessories' WHEN 6 THEN 'Lifestyle' WHEN 7 THEN 'Running'
    WHEN 8 THEN 'Training' WHEN 9 THEN 'Yoga' WHEN 10 THEN 'Running' ELSE 'Outdoor'
  END                                                             AS TOP_CATEGORY,
  (MOD(g.n, 10) > 1)                                             AS MARKETING_OPT_IN,
  (MOD(g.n, 5) > 1)                                              AS PUSH_OPT_IN,
  (MOD(g.n, 7) > 2)                                              AS SMS_OPT_IN,
  'STR-' || LPAD(MOD(g.n, 500) + 1, 3, '0')                     AS NEAREST_STORE_ID,
  DATEADD(day, -UNIFORM(30, 1825, RANDOM()), CURRENT_DATE())     AS SIGNUP_DATE,
  DATEADD(day, -UNIFORM(0, 90, RANDOM()), CURRENT_DATE())        AS LAST_LOGIN_DATE
FROM gen g
JOIN first_names fn ON fn.idx = MOD(g.n, 60)
JOIN last_names  ln ON ln.idx = MOD(g.n, 50)
JOIN states_data sd  ON sd.idx = MOD(g.n, 20);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.CUSTOMERS TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- EVENT_STREAM — 1,800,000 behavioral events
-- Cohort-aware purchase timestamps create all 8 RFM segments.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM (
  EVENT_ID          VARCHAR(20)   NOT NULL,
  CUSTOMER_ID       VARCHAR(12)   NOT NULL,
  EVENT_TYPE        VARCHAR(30)   NOT NULL,
  EVENT_TIMESTAMP   TIMESTAMP_NTZ NOT NULL,
  PRODUCT_ID        VARCHAR(15),
  CATEGORY_ID       VARCHAR(10),
  SESSION_ID        VARCHAR(20),
  CHANNEL           VARCHAR(20),
  DEVICE_TYPE       VARCHAR(20),
  EVENT_PROPERTIES  VARIANT
);

-- Base 1.8M behavioral events (all types, cohort-aware purchase timing)
INSERT INTO WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
WITH
  event_types AS (
    SELECT e.value::VARCHAR AS etype, e.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["page_view","add_to_cart","purchase","return","search","gear_review","training_log","goal_set","size_exchange","wishlist_add","page_view","page_view","add_to_cart","purchase","page_view"]'))) e
  ),
  devices AS (
    SELECT d.value::VARCHAR AS dev, d.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["mobile","desktop","tablet","mobile","mobile","desktop","mobile","tablet","mobile","desktop"]'))) d
  ),
  channels_list AS (
    SELECT c.value::VARCHAR AS ch, c.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["app","web","app","web","email","app","web","app","email","web"]'))) c
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 1800000)))
SELECT
  'EVT-' || LPAD(g.n + 1, 8, '0')                                 AS EVENT_ID,
  'CUST-' || LPAD(MOD(g.n, 50000) + 1, 6, '0')                   AS CUSTOMER_ID,
  et.etype                                                          AS EVENT_TYPE,
  CASE
    -- Cohort 7 (at-risk): purchases 181-365 days ago → in 12m window but stale → High churn
    WHEN MOD(MOD(g.n, 50000), 10) = 7 AND et.etype = 'purchase'
    THEN DATEADD(second, -UNIFORM(15638400, 31536000, RANDOM()), CURRENT_TIMESTAMP())
    -- Cohort 8 (dormant): purchases 366-730 days ago → outside 12m window → null purchase metrics
    WHEN MOD(MOD(g.n, 50000), 10) = 8 AND et.etype = 'purchase'
    THEN DATEADD(second, -UNIFORM(31536001, 63072000, RANDOM()), CURRENT_TIMESTAMP())
    -- All others: purchases 0-181 days ago → Low churn
    WHEN et.etype = 'purchase'
    THEN DATEADD(second, -UNIFORM(0, 15638400, RANDOM()), CURRENT_TIMESTAMP())
    ELSE DATEADD(second, -UNIFORM(0, 31536000, RANDOM()), CURRENT_TIMESTAMP())
  END                                                               AS EVENT_TIMESTAMP,
  'PRD-' || LPAD(MOD(g.n * 7, 1000) + 1, 4, '0')                  AS PRODUCT_ID,
  'CAT-' || LPAD(MOD(g.n, 12) + 1, 3, '0')                        AS CATEGORY_ID,
  'SES-' || LPAD(MOD(g.n, 500000) + 1, 7, '0')                    AS SESSION_ID,
  ch.ch                                                             AS CHANNEL,
  dev.dev                                                           AS DEVICE_TYPE,
  CASE et.etype
    WHEN 'purchase'     THEN PARSE_JSON('{"amount":' || ROUND(UNIFORM(25, 300, RANDOM()), 2) || ',"quantity":' || UNIFORM(1,3,RANDOM()) || '}')
    WHEN 'gear_review'  THEN PARSE_JSON('{"review_text":"Great product, fits perfectly and performs well during training sessions. Would recommend to fellow athletes.","rating":' || UNIFORM(3,5,RANDOM()) || '}')
    WHEN 'training_log' THEN PARSE_JSON('{"activity":"running","duration_min":' || UNIFORM(20,120,RANDOM()) || ',"distance_km":' || ROUND(UNIFORM(2,20,RANDOM()),1) || '}')
    WHEN 'goal_set'     THEN PARSE_JSON('{"goal_type":"race","target_date":"2025-09-15","goal_description":"Complete first marathon"}')
    WHEN 'add_to_cart'  THEN PARSE_JSON('{"price":' || ROUND(UNIFORM(25,250,RANDOM()),2) || ',"quantity":1}')
    WHEN 'search'       THEN PARSE_JSON('{"query":"running shoes trail","results_count":' || UNIFORM(5,50,RANDOM()) || '}')
    ELSE PARSE_JSON('{}')
  END                                                               AS EVENT_PROPERTIES
FROM gen g
JOIN event_types   et  ON et.idx  = MOD(g.n, 15)
JOIN devices       dev ON dev.idx = MOD(g.n, 10)
JOIN channels_list ch  ON ch.idx  = MOD(g.n, 10);

-- Extra 150K purchases for at-risk cohort (cohort 7) to boost F_SCORE into top quintile
INSERT INTO WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
WITH
  devices AS (
    SELECT d.value::VARCHAR AS dev, d.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["mobile","desktop","tablet","mobile","mobile","desktop","mobile","tablet","mobile","desktop"]'))) d
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 150000)))
SELECT
  'EVT-ATR-' || LPAD(g.n + 1, 7, '0')                            AS EVENT_ID,
  -- At-risk customers: CUST-000008, CUST-000018, ..., CUST-049998
  'CUST-' || LPAD(MOD(g.n, 5000) * 10 + 8, 6, '0')              AS CUSTOMER_ID,
  'purchase'                                                        AS EVENT_TYPE,
  DATEADD(second, -UNIFORM(15638400, 31536000, RANDOM()), CURRENT_TIMESTAMP()) AS EVENT_TIMESTAMP,
  'PRD-' || LPAD(MOD(g.n * 7, 1000) + 1, 4, '0')                 AS PRODUCT_ID,
  'CAT-' || LPAD(MOD(g.n, 12) + 1, 3, '0')                       AS CATEGORY_ID,
  'SES-' || LPAD(MOD(g.n, 500000) + 1, 7, '0')                   AS SESSION_ID,
  'app'                                                             AS CHANNEL,
  dev.dev                                                           AS DEVICE_TYPE,
  PARSE_JSON('{"amount":' || ROUND(UNIFORM(60, 250, RANDOM()), 2) || ',"quantity":' || UNIFORM(1,2,RANDOM()) || '}') AS EVENT_PROPERTIES
FROM gen g
JOIN devices dev ON dev.idx = MOD(g.n, 10);

-- 5 explicit purchases per all 50K customers (ensures all customers have purchase history)
-- Cohort-aware timing: dormant outside window, at-risk stale, others recent
INSERT INTO WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
WITH
  devices AS (
    SELECT d.value::VARCHAR AS dev, d.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["mobile","desktop","tablet","mobile","mobile","desktop","mobile","tablet","mobile","desktop"]'))) d
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 250000)))
SELECT
  'EVT-PUR-' || LPAD(g.n + 1, 8, '0')                            AS EVENT_ID,
  'CUST-' || LPAD(MOD(g.n, 50000) + 1, 6, '0')                   AS CUSTOMER_ID,
  'purchase'                                                        AS EVENT_TYPE,
  CASE
    WHEN MOD(MOD(g.n, 50000), 10) = 8
    THEN DATEADD(day, -UNIFORM(366, 730, RANDOM()), CURRENT_DATE())
    WHEN MOD(MOD(g.n, 50000), 10) = 7
    THEN DATEADD(day, -UNIFORM(181, 365, RANDOM()), CURRENT_DATE())
    ELSE DATEADD(day, -UNIFORM(0, 181, RANDOM()), CURRENT_DATE())
  END                                                               AS EVENT_TIMESTAMP,
  'PRD-' || LPAD(MOD(g.n * 7, 1000) + 1, 4, '0')                  AS PRODUCT_ID,
  'CAT-' || LPAD(MOD(g.n, 12) + 1, 3, '0')                        AS CATEGORY_ID,
  'SES-' || LPAD(MOD(g.n, 500000) + 1, 7, '0')                    AS SESSION_ID,
  'web'                                                             AS CHANNEL,
  dev.dev                                                           AS DEVICE_TYPE,
  PARSE_JSON('{"amount":' || ROUND(UNIFORM(30, 280, RANDOM()), 2) || ',"quantity":' || UNIFORM(1,3,RANDOM()) || '}') AS EVENT_PROPERTIES
FROM gen g
JOIN devices dev ON dev.idx = MOD(g.n, 10);

-- Cohort 9: replace with 2 medium-stale purchases (91-160 days) to create New/Medium segment
-- First delete the 5 "normal" purchases inserted above for cohort 9
DELETE FROM WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
WHERE EVENT_ID LIKE 'EVT-PUR-%'
  AND EVENT_TYPE = 'purchase'
  AND MOD(CAST(REPLACE(CUSTOMER_ID, 'CUST-0', '') AS INTEGER) - 1, 10) = 9;

INSERT INTO WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM
WITH
  devices AS (
    SELECT d.value::VARCHAR AS dev, d.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["mobile","desktop","tablet","mobile","mobile","desktop","mobile","tablet","mobile","desktop"]'))) d
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 10000)))
SELECT
  'EVT-NEW-' || LPAD(g.n + 1, 7, '0')                             AS EVENT_ID,
  'CUST-' || LPAD(MOD(g.n, 5000) * 10 + 10, 6, '0')              AS CUSTOMER_ID,
  'purchase'                                                        AS EVENT_TYPE,
  DATEADD(day, -UNIFORM(91, 160, RANDOM()), CURRENT_DATE())        AS EVENT_TIMESTAMP,
  'PRD-' || LPAD(MOD(g.n * 7, 1000) + 1, 4, '0')                  AS PRODUCT_ID,
  'CAT-' || LPAD(MOD(g.n, 12) + 1, 3, '0')                        AS CATEGORY_ID,
  'SES-' || LPAD(MOD(g.n, 500000) + 1, 7, '0')                    AS SESSION_ID,
  'web'                                                             AS CHANNEL,
  dev.dev                                                           AS DEVICE_TYPE,
  PARSE_JSON('{"amount":' || ROUND(UNIFORM(40, 150, RANDOM()), 2) || ',"quantity":1}') AS EVENT_PROPERTIES
FROM gen g
JOIN devices dev ON dev.idx = MOD(g.n, 10);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM TO ROLE WRITER_MARKETING_ROLE;

-- ---------------------------------------------------------------------------
-- CAMPAIGN_EVENTS — 156,000 campaign interaction events
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS (
  EVENT_ID          VARCHAR(20)   NOT NULL,
  CAMPAIGN_ID       VARCHAR(15)   NOT NULL,
  CUSTOMER_ID       VARCHAR(12)   NOT NULL,
  EVENT_TYPE        VARCHAR(20)   NOT NULL,
  EVENT_TIMESTAMP   TIMESTAMP_NTZ NOT NULL,
  CHANNEL           VARCHAR(20),
  DEVICE_TYPE       VARCHAR(20),
  REVENUE           NUMBER(10,2),
  PROMO_CODE_USED   VARCHAR(20)
);

INSERT INTO WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS
WITH
  campaigns AS (
    SELECT c.value::VARCHAR AS cid, c.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["CMP-2025-001","CMP-2025-006","CMP-2025-016","CMP-2025-026","CMP-2025-061","CMP-2025-081"]'))) c
  ),
  ce_event_types AS (
    SELECT e.value::VARCHAR AS etype, e.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["send","send","send","open","open","click","convert","send","open","click","send","open","convert","click","send","send","open","click","send","bounce"]'))) e
  ),
  ce_channels AS (
    SELECT c.value::VARCHAR AS ch, c.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["email","email","push","email","sms","email","email","push","email","email"]'))) c
  ),
  ce_devices AS (
    SELECT d.value::VARCHAR AS dev, d.index AS idx
    FROM TABLE(FLATTEN(PARSE_JSON('["mobile","desktop","mobile","tablet","mobile","desktop","mobile","mobile","desktop","tablet"]'))) d
  ),
  gen AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 156000)))
SELECT
  'CEV-' || LPAD(g.n + 1, 7, '0')                                 AS EVENT_ID,
  camp.cid                                                          AS CAMPAIGN_ID,
  'CUST-' || LPAD(MOD(g.n, 50000) + 1, 6, '0')                   AS CUSTOMER_ID,
  cet.etype                                                         AS EVENT_TYPE,
  DATEADD(second, -UNIFORM(0, 15768000, RANDOM()), CURRENT_TIMESTAMP()) AS EVENT_TIMESTAMP,
  cch.ch                                                            AS CHANNEL,
  cdev.dev                                                          AS DEVICE_TYPE,
  CASE WHEN cet.etype = 'convert' THEN ROUND(UNIFORM(35, 280, RANDOM()), 2) ELSE NULL END AS REVENUE,
  CASE WHEN cet.etype = 'convert' AND MOD(g.n, 3) = 0 THEN 'WINBACK25'
       WHEN cet.etype = 'convert' AND MOD(g.n, 3) = 1 THEN 'WELCOME10'
       ELSE NULL
  END                                                               AS PROMO_CODE_USED
FROM gen g
JOIN campaigns     camp ON camp.idx = MOD(g.n, 6)
JOIN ce_event_types cet ON cet.idx  = MOD(g.n, 20)
JOIN ce_channels    cch ON cch.idx  = MOD(g.n, 10)
JOIN ce_devices    cdev ON cdev.idx = MOD(g.n, 10);

GRANT SELECT ON TABLE WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS TO ROLE WRITER_MARKETING_ROLE;
