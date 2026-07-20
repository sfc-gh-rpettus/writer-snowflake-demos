#!/bin/bash
# =============================================================================
# run_all.sh — Apex Athletics Content Supply Chain Demo Setup
# Runs all setup scripts in order against a Snowflake connection.
#
# Prerequisites:
#   • Snowflake CLI installed: https://docs.snowflake.com/en/developer-guide/snowflake-cli
#   • Connection configured: snow connection add (or use an existing one)
#   • Account must have Cortex AI enabled (Enterprise+ or Trial)
#
# Usage:
#   chmod +x run_all.sh
#   ./run_all.sh demo490          # use named connection
#   ./run_all.sh                  # uses SNOW_DEFAULT_CONNECTION env var
#
# Skip phase 2 (saves ~20 min on slow accounts):
#   SKIP_PHASE2=1 ./run_all.sh demo490
# =============================================================================

set -e  # exit on first error

CONNECTION="${1:-${SNOW_DEFAULT_CONNECTION:-default}}"
SKIP_PHASE2="${SKIP_PHASE2:-0}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPTS_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

# Color helpers
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

header()  { echo -e "\n${BLUE}${BOLD}══ $1 ══${RESET}"; }
success() { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail()    { echo -e "  ${RED}✗${RESET} $1"; }
info()    { echo -e "  ${BOLD}→${RESET} $1"; }

echo ""
echo -e "${BOLD}Apex Athletics Content Supply Chain — Setup${RESET}"
echo "Connection: $CONNECTION"
echo "Log file:   $LOG_FILE"
echo ""

# Check snow CLI is available
if ! command -v snow &>/dev/null; then
  echo "snow CLI not found. Install from:"
  echo "  https://docs.snowflake.com/en/developer-guide/snowflake-cli"
  echo ""
  echo "Alternatively, run each script manually in Snowsight in this order:"
  ls "$SCRIPTS_DIR"/*.sql | sort | grep -v run_all
  exit 1
fi

run_script() {
  local file="$1"
  local label="$2"
  local est="$3"

  header "$label  (~$est)"
  info "Running $file ..."

  if snow sql -f "$SCRIPTS_DIR/$file" -c "$CONNECTION" >> "$LOG_FILE" 2>&1; then
    success "$label complete"
  else
    fail "$label FAILED — see $LOG_FILE"
    echo ""
    warn "Check SETUP_NOTES.md in this folder for known issues and fixes."
    exit 1
  fi
}

# ── Phase 1: Environment ─────────────────────────────────────────────────────
header "PHASE 1 — Environment & Reference Data"

warn "If this is a fresh account, uncomment the ACCOUNTADMIN block in"
warn "00_setup.sql and run it first to grant CREATE AGENT / CREATE MCP SERVER."
echo ""

run_script "00_setup.sql"             "Environment setup"             "30 sec"
run_script "01_reference_tables.sql"  "Reference tables"              "30 sec"

# ── Phase 2: Bronze Data ─────────────────────────────────────────────────────
header "PHASE 2 — Bronze Data Generation"
warn "This generates 2.2M rows. May take 5–10 min on a MEDIUM warehouse."

run_script "02_generate_bronze.sql"   "Bronze data (50K customers / 2.2M events)" "5-10 min"

# ── Phase 3: Gold Layer ──────────────────────────────────────────────────────
header "PHASE 3 — Dynamic Tables"

run_script "04_dynamic_tables.sql"    "CUSTOMER_360 + MICRO_SEGMENTS DTs"  "1 min (init)"
info "DTs are initializing in background — continuing with next scripts..."
echo ""

# ── Phase 4: Content Supply Chain Objects ───────────────────────────────────
header "PHASE 4 — Content Supply Chain Objects"

run_script "05_campaign_library.sql"  "Campaign library (100 AI-generated)" "3-5 min"
run_script "06_content_tables.sql"    "Write-back tables (empty at demo start)" "15 sec"
run_script "07_stored_procedures.sql" "MCP stored procedures"               "15 sec"

# ── Phase 5: AI Layer ────────────────────────────────────────────────────────
header "PHASE 5 — Cortex Search, Semantic View, Agent"

run_script "08_cortex_search.sql"     "Cortex Search services"              "1 min"
info "Cortex Search indexing in background (1-5 min). Agent creation continues..."
echo ""

run_script "09_semantic_view.sql"     "CUSTOMER_360_SV Semantic View"       "15 sec"
run_script "10_cortex_agent.sql"      "MARKETING_CAMPAIGN_PLANNER Agent"    "15 sec"
run_script "11_mcp_server.sql"        "MARKETING_MCP_SERVER (5 tools)"      "15 sec"

# ── Phase 6: Analytics ───────────────────────────────────────────────────────
header "PHASE 6 — Performance Analytics"

run_script "12_perf_gold.sql"         "CAMPAIGN_PERFORMANCE_GOLD DT"        "1 min"

# ── Phase 7: Phase 2 Objects (optional) ─────────────────────────────────────
if [ "$SKIP_PHASE2" = "1" ]; then
  header "PHASE 7 — Phase 2 Objects (SKIPPED)"
  warn "Skipping 13_phase2_objects.sql (SKIP_PHASE2=1)."
  warn "Run manually later: snow sql -f 13_phase2_objects.sql -c $CONNECTION"
else
  header "PHASE 7 — Phase 2 Objects"
  warn "CORTEX.SENTIMENT on ~120K gear reviews. May take 10-20 min."
  warn "Safe to skip for Phase 1 demo: SKIP_PHASE2=1 ./run_all.sh $CONNECTION"
  echo ""
  run_script "13_phase2_objects.sql"  "Phase 2: sentiment, GEO, brand voice" "10-20 min"
fi

# ── Final Grants ─────────────────────────────────────────────────────────────
header "FINAL — Grant Sweep"

run_script "14_grants.sql"            "Final grant sweep"                   "15 sec"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║  Setup complete!                         ║"
echo -e "╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "Next steps:"
echo "  1. Wait ~5 min for Cortex Search to finish indexing"
echo "  2. Test the agent:"
echo '     snow sql -c '"$CONNECTION"' -q "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('\''WRITER.MARKETING.MARKETING_CAMPAIGN_PLANNER'\'', '\''What are the top 5 segments by intent score?'\'')"'
echo "  3. Before each demo run: snow sql -f 99_demo_reset.sql -c $CONNECTION"
echo ""
echo "Log saved to: $LOG_FILE"
echo "Issues? See: $SCRIPTS_DIR/SETUP_NOTES.md"
