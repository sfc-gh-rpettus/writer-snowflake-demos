# Apex Athletics — Content Supply Chain Demo Setup

**Schema:** `WRITER_SNOW_DEMO.MARKETING` | **Build role:** SYSADMIN  
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
./run_all.sh <your-connection>
```

To skip Phase 2 objects (not needed for Phase 1 demo):
```bash
SKIP_PHASE2=1 ./run_all.sh <your-connection>
```


---

## Option B — Snowsight (no CLI required)

Open each script in a Snowsight worksheet and run in order. Use **Run All** (⌘+Shift+Enter).

| Step | Script | Notes |
|------|--------|-------|
| 1 | `01_setup_and_foundation.sql` | ⚠️ See "Fresh Account" note below. Includes env + all reference tables. |
| 2 | `02_bronze_data.sql` | Generates 50K customers, 2.2M events — recommend MEDIUM+ warehouse |
| 3 | `03_data_model.sql` | DTs + AI-generated campaign library (CORTEX.COMPLETE calls) + write-back tables + procs |
| 4 | `04_ai_layer.sql` | Cortex Search + Semantic View + Agent + MCP Server. Allow time for Search indexing after. |
| 5 | `05_analytics_and_grants.sql` | Performance analytics DT + final grant sweep |
| 6 | `06_phase2_optional.sql` | **Optional** — not needed for Phase 1 demo |

---

## Fresh Account Setup

On a fresh Snowflake account, SYSADMIN does not have `CREATE AGENT` or `CREATE MCP SERVER` by default.

**Before running `01_setup_and_foundation.sql`**, uncomment and run the ACCOUNTADMIN block at the top:

```sql
USE ROLE ACCOUNTADMIN;
GRANT CREATE DYNAMIC TABLE         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE SEMANTIC VIEW         ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE AGENT                 ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
GRANT CREATE MCP SERVER            ON SCHEMA WRITER_SNOW_DEMO.MARKETING TO ROLE SYSADMIN;
```

Also update the `DEMO_USER` in `01_setup_and_foundation.sql` to your actual Snowflake username.

---

## OAuth / Writer MCP Authentication

Writer connects to the MCP server via OAuth using the `WRITER_OAUTH` security integration.

### What's already configured
- `WRITER_OAUTH` Custom OAuth integration exists in this account
- Redirect URI is set to `https://app.writer.com/mcp/oauth/callback`
- `GRANT USAGE ON INTEGRATION WRITER_OAUTH TO ROLE WRITER_MARKETING_ROLE` is in `01_setup_and_foundation.sql`

### Connecting Writer to Snowflake

When setting up the Snowflake integration in Writer ("Configure Snowflake"), you need three things from your Snowflake account. Run the queries at the end of `04_ai_layer.sql` to get them:

**Step 1 — Get the MCP Server URL and account info:**
```sql
SELECT
  'https://' || LOWER(CURRENT_ORGANIZATION_NAME()) || '-' || LOWER(CURRENT_ACCOUNT_NAME())
    || '.snowflakecomputing.com'
    || '/api/v2/databases/WRITER_SNOW_DEMO/schemas/MARKETING/mcp-servers/MARKETING_MCP_SERVER'
    AS mcp_server_url,
  LOWER(CURRENT_ORGANIZATION_NAME()) || '-' || LOWER(CURRENT_ACCOUNT_NAME()) AS snowflake_account;
```

**Step 2 — Get the OAuth client ID and secret:**
```sql
-- Integration name must be UPPERCASE
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WRITER_OAUTH') AS oauth_credentials;
```
This returns a JSON object with `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET`. Treat these as passwords.

**What goes in each Writer field:**

| Writer Field | Value |
|---|---|
| **Tenant URL** (MCP Server URL) | Output of Step 1 `mcp_server_url` — full `/api/v2/...` URL |
| **OAuth 2.0 Client ID** | `OAUTH_CLIENT_ID` from Step 2 JSON |
| **OAuth 2.0 Client Secret** | `OAUTH_CLIENT_SECRET` from Step 2 JSON |

> **Important:** The MCP session runs as the connecting user's `DEFAULT_ROLE`. Make sure the user authenticating via Writer has `WRITER_MARKETING_ROLE` set as their default role:
> ```sql
> ALTER USER <your_username> SET DEFAULT_ROLE = 'WRITER_MARKETING_ROLE'
>                              DEFAULT_WAREHOUSE = 'WRITER_WH';
> ```

### OAuth Security Integration (fresh account setup)

If `WRITER_OAUTH` doesn't yet exist, uncomment the `CREATE SECURITY INTEGRATION` block in `01_setup_and_foundation.sql` and run it as ACCOUNTADMIN. Key settings:

- **`ALLOWED_ROLES_LIST = ('WRITER_MARKETING_ROLE')`** — restricts OAuth to only this role
- **`OAUTH_USE_SECONDARY_ROLES = IMPLICIT`** — optional; include if you want to leverage secondary roles in the OAuth session
- **`OAUTH_REDIRECT_URI`** — must match exactly what Writer shows during connector setup

### Role access checklist for WRITER_MARKETING_ROLE

| Privilege | Object | Status |
|-----------|--------|--------|
| USAGE | MARKETING_MCP_SERVER | ✅ |
| USAGE | MARKETING_CAMPAIGN_PLANNER (Agent) | ✅ |
| USAGE | CAMPAIGN_LIBRARY_SEARCH (Cortex Search) | ✅ |
| USAGE | CAMPAIGN_BRIEFS_SEARCH (Cortex Search) | ✅ |
| SELECT | CUSTOMER_360_SV (Semantic View) | ✅ |
| USAGE | ACTIVATE_SEGMENT, SAVE_BRIEF, SAVE_CONTENT_ASSET (Procs) | ✅ |
| SELECT + INSERT | CAMPAIGN_BRIEFS, CONTENT_ASSETS, CAMPAIGN_AUDIENCES | ✅ |
| INSERT | CAMPAIGN_EVENTS (needed for flywheel seeding in ACTIVATE_SEGMENT) | ✅ |
| SELECT | All other tables + Dynamic Tables | ✅ |
| USAGE | WRITER_WH warehouse | ✅ |
| USAGE | WRITER_OAUTH integration | ✅ |

---

## Tear Down

To wipe all demo objects and start fresh:

```bash
snow sql -f 99_teardown.sql -c <your-connection>
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
snow sql -f 99_demo_reset.sql -c <your-connection>
```

---

## Troubleshooting

See **SETUP_NOTES.md** for all known issues and fixes.

| Error | Fix |
|-------|-----|
| `CREATE AGENT failed` | Uncomment ACCOUNTADMIN block in `01_setup_and_foundation.sql` |
| `Model "claude-haiku-4-5" unavailable` | Enable cross-region inference or check regional availability |
| `Agent returned empty response` | Verify `execution_environment.warehouse: WRITER_WH` in `10_cortex_agent.sql` |
| `WRITER_OAUTH: insufficient privileges` | Ensure `GRANT USAGE ON INTEGRATION WRITER_OAUTH` ran successfully |
| `CORTEX.SENTIMENT timeout` | Run `13_phase2_objects.sql` on LARGE warehouse or skip (not needed for Phase 1) |
