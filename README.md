# Writer × Snowflake Demo Repository

A collection of Snowflake demo environments that showcase the Writer + Snowflake integration — including Cortex Agents, MCP Servers, Semantic Views, and the full content supply chain flywheel.

Each demo is self-contained in its own folder with numbered SQL scripts, a setup guide, and a teardown script.

---

## Demos

| Demo | Description | Status |
|------|-------------|--------|
| [Content Supply Chain](./content-supply-chain/) | Apex Athletics activewear brand — full content supply chain demo with Cortex Agent, MCP Server, 22 micro-segments, Writer write-back | Ready |

---

## Prerequisites (all demos)

- Snowflake account with **Cortex AI enabled** (Enterprise+ or Trial)
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli) installed (`snow` command)
- SYSADMIN or ACCOUNTADMIN access
- `WRITER_OAUTH` security integration configured (see [OAuth Setup](#oauth-setup) below)

---

## OAuth Setup

All demos use the `WRITER_OAUTH` Custom OAuth security integration to allow Writer's MCP client to authenticate with Snowflake.

**If `WRITER_OAUTH` already exists in your account:** no action needed — the integration is referenced in each demo's `00_setup.sql` (the `CREATE SECURITY INTEGRATION` block is commented out).

**If setting up on a fresh account:** uncomment the `CREATE SECURITY INTEGRATION` block in `00_setup.sql` of the relevant demo and run it as ACCOUNTADMIN before running any other scripts. Writer's team will provide the OAuth client credentials to configure in Writer's application.

```sql
-- Run as ACCOUNTADMIN on a fresh account
USE ROLE ACCOUNTADMIN;
CREATE SECURITY INTEGRATION IF NOT EXISTS WRITER_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://app.writer.com/mcp/oauth/callback'
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 7776000
  OAUTH_USE_SECONDARY_ROLES = IMPLICIT
  BLOCKED_ROLES_LIST = ('ACCOUNTADMIN', 'ORGADMIN', 'SECURITYADMIN');

-- After creation, retrieve the client ID to share with Writer:
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WRITER_OAUTH');
```

> **Never commit OAuth client secrets, passwords, or account-specific credentials to this repository.**

---

## Repository Structure

```
writer-snowflake-demos/
├── README.md                              ← You are here
├── .gitignore
├── LICENSE
└── content-supply-chain/
    └── scripts/
        ├── README.md                      ← Demo-specific setup guide
        ├── run_all.sh                     ← One-command setup
        ├── 01_setup_and_foundation.sql    ← Database, schema, role, reference tables
        ├── 02_bronze_data.sql             ← 50K customers, 2.2M events
        ├── 03_data_model.sql              ← DTs, campaign library, write-back tables, procs
        ├── 04_ai_layer.sql                ← Cortex Search, Semantic View, Agent, MCP Server
        ├── 05_analytics_and_grants.sql    ← Performance DT + final grants
        ├── 06_phase2_optional.sql         ← Sentiment, GEO, brand voice (optional)
        ├── 99_demo_reset.sql              ← Reset between demo runs
        ├── 99_teardown.sql                ← Full teardown (decommission only)
        └── SETUP_NOTES.md                 ← Known issues and fixes
```

---

## Quick Start

```bash
# 1. Clone the repo
git clone <repo-url>
cd writer-snowflake-demos

# 2. Run a demo (Content Supply Chain)
cd content-supply-chain/scripts
./run_all.sh <your-snowflake-connection>

# 3. Reset before each demo run
snow sql -f 99_demo_reset.sql -c <your-snowflake-connection>
```

See each demo's `scripts/README.md` for full prerequisites and setup details.

---

## Contributing

To add a new demo:
1. Create a branch: `git checkout -b feature/<demo-name>`
2. Add a folder: `<demo-name>/scripts/`
3. Follow the script numbering convention: `00_setup.sql` → `14_grants.sql` + `99_reset.sql`
4. Add a `README.md` inside `scripts/` and a row to the Demos table above
5. Run the secret scan before committing: `grep -r "snowflakecomputing.com\|password\|secret\|token" scripts/`
