# Apex Athletics — Content Supply Chain Demo Setup

**Schema:** `WRITER_SNOW_DEMO.MARKETING` | **Account:** demo490 | **Build role:** SYSADMIN  
**Demo role:** `WRITER_MARKETING_ROLE` | **OAuth integration:** `WRITER_OAUTH`

---

## Role Architecture

All objects are **created and owned by SYSADMIN**. `WRITER_MARKETING_ROLE` receives USAGE/SELECT grants on everything. This is the only role used in the demo itself.

```
ACCOUNTADMIN
  └── SYSADMIN (builds everything)
        └── WRITER_MARKETING_ROLE (demo + Writer MCP connection)
              └── DEMO_USER (SE running the demo)
```

---

## Prerequisites

- Snowflake account with **Cortex AI enabled** (Enterprise+ or Trial)
- SYSADMIN or ACCOUNTADMIN access
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli) installed (`snow` command)
- `WRITER_OAUTH` security integration must exist (pre-configured for Writer's MCP client)

**Verify Cortex is available:**
```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-haiku-4-5', 'ping') AS test;
```

---

## Option A — One command (recommended)

```bash
cd scripts/
./run_all.sh demo490
```

To skip Phase 2 objects (saves 10–20 min, not needed for Phase 1 demo):
```bash
SKIP_PHASE2=1 ./run_all.sh demo490
```

**Expected total runtime:** ~25–35 min with SKIP_PHASE2=1, ~45–60 min full.

---

## Option B — Snowsight (no CLI required)

Open each script in a Snowsight worksheet and run in order. Use **Run All** (⌘+Shift+Enter).

| Step | Script | Est. Time | Notes |
|------|--------|-----------|-------|
| 1 | `00_setup.sql` | 30 sec | ⚠️ See "Fresh Account" note below |
| 2 | `01_reference_tables.sql` | 30 sec | |
| 3 | `02_generate_bronze.sql` | 5–10 min | Generates 2.2M rows |
| 4 | `04_dynamic_tables.sql` | 1 min | DTs initialize in background |
| 5 | `05_campaign_library.sql` | 3–5 min | 300 CORTEX.COMPLETE calls |
| 6 | `06_content_tables.sql` | 15 sec | |
| 7 | `07_stored_procedures.sql` | 15 sec | |
| 8 | `08_cortex_search.sql` | 1 min | Wait 1–5 min after for indexing |
| 9 | `09_semantic_view.sql` | 15 sec | |
| 10 | `10_cortex_agent.sql` | 15 sec | |
| 11 | `11_mcp_server.sql` | 15 sec | |
| 12 | `12_perf_gold.sql` | 1 min | |
| 13 | `13_phase2_objects.sql` | 10–20 min | Optional — not needed for Phase 1 |
| 14 | `14_grants.sql` | 15 sec | |

---

## Fresh Account Setup

On a fresh Snowflake account, SYSADMIN does not have `CREATE AGENT` or `CREATE MCP SERVER` by default.

**Before running `00_setup.sql`**, uncomment and run the ACCOUNTADMIN block at the top:

```sql
USE ROLE ACCOUNTADMIN;
GRANT CREATE DYNAMIC TABLE         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE SEMANTIC VIEW         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE AGENT                 ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE MCP SERVER            ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
```

Also update the `DEMO_USER` in `00_setup.sql` to your actual Snowflake username.

---

## OAuth / Writer MCP Authentication

Writer connects to the MCP server via OAuth using the `WRITER_OAUTH` security integration.

### What's already configured
- `WRITER_OAUTH` Custom OAuth integration exists in this account
- Redirect URI is set to `https://app.writer.com/mcp/oauth/callback`
- `GRANT USAGE ON INTEGRATION WRITER_OAUTH TO ROLE WRITER_MARKETING_ROLE` is in `00_setup.sql`

### What Writer's team needs to configure in Writer
To connect Writer to the MCP server, provide Writer's team with:

| Setting | Value |
|---------|-------|
| **Snowflake Account** | `<YOUR_SNOWFLAKE_ACCOUNT>` (e.g. `myorg-myaccount`) |
| **MCP Server Name** | `WRITER_SNOW_DEMO.MARKETING.MARKETING_MCP_SERVER` |
| **Role** | `WRITER_MARKETING_ROLE` |
| **OAuth Integration** | `WRITER_OAUTH` — Writer retrieves credentials from this integration |
| **Warehouse** | `WRITER_WH` |

> The OAuth client ID and secret for `WRITER_OAUTH` are managed in Writer's application configuration. Do not include these in any scripts or documentation.

### Verify the OAuth integration is accessible
```sql
USE ROLE WRITER_MARKETING_ROLE;
SHOW INTEGRATIONS LIKE 'WRITER_OAUTH';  -- should return 1 row
```

---

## Tear Down

To wipe all demo objects and start fresh:

```bash
snow sql -f 00_teardown.sql -c demo490
```

This drops `WRITER_SNOW_DEMO.MARKETING` schema and `WRITER_MARKETING_ROLE`. It does **not** touch other schemas or databases.

---

## Verify Setup

After all scripts complete:

```sql
-- Row counts
SELECT 'CUSTOMERS'        AS obj, COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMERS        -- 50,000
UNION ALL SELECT 'EVENT_STREAM',       COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.EVENT_STREAM -- ~2.2M
UNION ALL SELECT 'CAMPAIGN_EVENTS',    COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_EVENTS -- 156,000
UNION ALL SELECT 'CUSTOMER_360',       COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.CUSTOMER_360    -- 50,000
UNION ALL SELECT 'MICRO_SEGMENTS',     COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.MICRO_SEGMENTS  -- 22
UNION ALL SELECT 'CAMPAIGN_LIBRARY',   COUNT(*) FROM WRITER_SNOW_DEMO.MARKETING.CAMPAIGN_LIBRARY -- 100;

-- MCP Server visible
SHOW MCP SERVERS IN SCHEMA WRITER_SNOW_DEMO.MARKETING;  -- MARKETING_MCP_SERVER

-- Agent visible  
SHOW AGENTS IN SCHEMA WRITER_SNOW_DEMO.MARKETING;  -- MARKETING_CAMPAIGN_PLANNER
```

---

## Before Each Demo

```bash
snow sql -f 99_demo_reset.sql -c demo490
```

---

## Troubleshooting

See **SETUP_NOTES.md** for all known issues and fixes.

| Error | Fix |
|-------|-----|
| `CREATE AGENT failed` | Uncomment ACCOUNTADMIN block in `00_setup.sql` |
| `Model "claude-haiku-4-5" unavailable` | Enable cross-region inference or check regional availability |
| `Agent returned empty response` | Verify `execution_environment.warehouse: WRITER_WH` in `10_cortex_agent.sql` |
| `WRITER_OAUTH: insufficient privileges` | Ensure `GRANT USAGE ON INTEGRATION WRITER_OAUTH` ran successfully |
| `CORTEX.SENTIMENT timeout` | Run `13_phase2_objects.sql` on LARGE warehouse or skip (not needed for Phase 1) |
