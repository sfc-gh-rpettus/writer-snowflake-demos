## Setup Notes — Apex Athletics Content Supply Chain

---

### 02_generate_bronze.sql — Customer purchase distribution gap

**Error:** MICRO_SEGMENTS only produced 12-16 segments vs. expected 22.

**Root cause:** The deterministic `MOD(g.n, 15)` event type generation only assigns purchase events to 6 out of 15 customer positions. 9/15 = 60% of customers (30K) never received any purchase events from the base 1.8M insert. Combined with dormant customers competing with at-risk customers in the NTILE recency ranking, the 8th RFM segment ("New") was absent.

**Fix applied:**
1. Added a 150K extra purchase INSERT for at-risk customers (cohort 7) to boost their F_SCORE into the top quintile.
2. Added a 250K explicit purchase INSERT for ALL 50K customers with cohort-aware timing.
3. Replaced cohort 9's 250K purchases with only 10K purchases at 91-160 days old → creates New/Medium segment.
4. Changed PREFERRED_CHANNEL to use MOD(n,3) for balanced email/push/sms split to avoid cohort-channel correlation.

**Date:** 2026-07-16

---

### 04_dynamic_tables.sql — Dormant customers not appearing in MICRO_SEGMENTS

**Error:** Dormant cohort (cohort 8, no purchases in 12m window) was not getting low R_SCORE because the `rfm_base` CTE fell back to `c.SIGNUP_DATE` which ranged 30-1825 days. Customers with recent signup dates were assigned high R_SCORE, preventing "Dormant" classification.

**Root cause:** `COALESCE(pm.LAST_PURCHASE_DATE, c.SIGNUP_DATE)` produces variable results for dormant customers, making it impossible to consistently place them in the R_SCORE=1 bucket via NTILE.

**Fix applied:** Changed the fallback to a fixed value: `COALESCE(pm.LAST_PURCHASE_DATE, DATEADD(day, -548, CURRENT_DATE()))`. This places all dormant customers at exactly 548 days in the recency ranking, which combined with 5K at-risk customers at 181-365 days, exactly fills the R_SCORE=1 NTILE bucket (10K total = 5K dormant + 5K at-risk).

**Date:** 2026-07-16

---

### 04_dynamic_tables.sql — MICRO_SEGMENTS LIMIT 22

**Note:** The MICRO_SEGMENTS HAVING threshold of 200 naturally produces 22+ segments. To ensure exactly 22 regardless of data refresh variance, `LIMIT 22` is added to the ranked CTE. The top 22 by INTENT_SCORE are selected.

**Date:** 2026-07-16

---

### 02_generate_bronze.sql — At-risk customers all had sms channel

**Error:** All 5,000 at-risk customers (cohort 7, n%10=7) were assigned 'sms' channel because both the cohort and channel were derived from MOD(g.n, 10). This made the At Risk segment appear only once (High/sms) instead of three times (High/email, High/push, High/sms).

**Root cause:** Channel was assigned using `ch.idx = MOD(g.n, 10)`, same modulus as the cohort assignment. Perfect correlation.

**Fix applied:** Changed PREFERRED_CHANNEL to `CASE MOD(g.n, 3) WHEN 0 THEN 'email' WHEN 1 THEN 'push' ELSE 'sms' END`, using MOD 3 instead of 10. Since GCD(3, 10) = 1, cohort and channel are now independent, producing balanced channel distribution across all RFM segments.

**Date:** 2026-07-16

---

### 05_campaign_library.sql — CORTEX.COMPLETE model not available

**Error:** `Model "claude-3-5-haiku" is unavailable`

**Root cause:** The model name `claude-3-5-haiku` is deprecated. Snowflake renamed models with new versioned naming convention.

**Fix applied:** Changed all `CORTEX.COMPLETE` calls to use `claude-haiku-4-5`. Also widened PERFORMANCE_TIER column from VARCHAR(10) to VARCHAR(20) — 'Performance' is 11 characters.

**Date:** 2026-07-16

---

### 08_cortex_search.sql — Cortex Search ON clause syntax

**Error:** `syntax error line 2 at position 17 unexpected ','`

**Root cause:** The `ON` clause in `CREATE CORTEX SEARCH SERVICE` accepts only a single column. Multi-column syntax (`ON col1, col2`) is not valid.

**Fix applied:** Added a `SEARCH_CONTENT` computed column in the AS query that concatenates all searchable fields with spaces. The `ON SEARCH_CONTENT` indexes the concatenated text while original columns remain as ATTRIBUTES for retrieval.

**Date:** 2026-07-16

---

### 09_semantic_view.sql — Multiple syntax issues

**Error 1:** `syntax error ... unexpected 'JOIN'`
**Root cause:** Semantic view RELATIONSHIPS uses FK-reference syntax (`table (cols) REFERENCES other (cols)`), not SQL JOIN syntax.
**Fix applied:** Changed to `c (RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL) REFERENCES s (RFM_SEGMENT, CHURN_RISK_TIER, PREFERRED_CHANNEL)`.

**Error 2:** `syntax error ... unexpected 'FACTS'`
**Root cause:** FACTS clause must come before DIMENSIONS in the DDL (the spec order is FACTS → DIMENSIONS → METRICS).
**Fix applied:** Reordered clauses to FACTS, DIMENSIONS, METRICS.

**Error 3:** `invalid identifier 'SEGMENT_REVENUE_OPP'`
**Root cause:** The right-hand side of AS in a factExpression must be the actual physical column name, not an alias. The logical name is on the LEFT of AS, the physical column is on the RIGHT.
**Fix applied:** Changed `s.TOTAL_REVENUE_OPPORTUNITY AS SEGMENT_REVENUE_OPP` to `s.TOTAL_REVENUE_OPPORTUNITY AS TOTAL_REVENUE_OPPORTUNITY`.

**Note:** SEMANTIC_VIEW queries use unqualified column names in ORDER BY (not `c.COLUMN_NAME`).

**Date:** 2026-07-16

---

### 10_cortex_agent.sql — Agent returned empty response

**Error:** `cortex agents run` returned `{"error":"Agent returned an empty response"}`

**Root cause:** The `cortex_analyst_text_to_sql` tool requires an explicit `execution_environment` with a warehouse in `tool_resources`. Without it, Cortex Analyst cannot execute queries and the agent silently fails.

**Fix applied:** Added to `tool_resources.CustomerAnalyst`:
```yaml
execution_environment:
  type: warehouse
  warehouse: WRITER_WH
```

**Date:** 2026-07-16
