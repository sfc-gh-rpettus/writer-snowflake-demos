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
# Skip Phase 2 (saves ~20 min — not needed for Phase 1 demo):
#   SKIP_PHASE2=1 ./run_all.sh demo490
# =============================================================================

set -e

CONNECTION="${1:-${SNOW_DEFAULT_CONNECTION:-default}}"
SKIP_PHASE2="${SKIP_PHASE2:-0}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPTS_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

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

if ! command -v snow &>/dev/null; then
  echo "snow CLI not found. Install from:"
  echo "  https://docs.snowflake.com/en/developer-guide/snowflake-cli"
  echo ""
  echo "Or run each script manually in Snowsight in this order:"
  ls "$SCRIPTS_DIR"/*.sql | sort | grep -v teardown
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
    warn "Check SETUP_NOTES.md for known issues and fixes."
    exit 1
  fi
}

# ── Step 1 ────────────────────────────────────────────────────────────────────
warn "If fresh account: uncomment ACCOUNTADMIN block in 01_setup_and_foundation.sql"
warn "Also replace DEMO_USER with your actual Snowflake username"
echo ""

run_script "01_setup_and_foundation.sql" \
  "Environment + reference tables" "30 sec"

# ── Step 2 ────────────────────────────────────────────────────────────────────
warn "This generates 2.2M rows — may take 5–10 min on a MEDIUM warehouse."

run_script "02_bronze_data.sql" \
  "Bronze data (50K customers / 2.2M events)" "5-10 min"

# ── Step 3 ────────────────────────────────────────────────────────────────────
info "Dynamic Tables initialize in background — continuing while they process..."
echo ""

run_script "03_data_model.sql" \
  "Gold DTs + Campaign library + Write-back tables + Procedures" "5-8 min"

# ── Step 4 ────────────────────────────────────────────────────────────────────
run_script "04_ai_layer.sql" \
  "Cortex Search + Semantic View + Agent + MCP Server" "2-3 min"

info "Cortex Search indexing in background (1–5 min after creation)"
echo ""

# ── Step 5 ────────────────────────────────────────────────────────────────────
run_script "05_analytics_and_grants.sql" \
  "Performance analytics DT + Final grant sweep" "1-2 min"

# ── Step 6 (optional) ─────────────────────────────────────────────────────────
if [ "$SKIP_PHASE2" = "1" ]; then
  header "Step 6 — Phase 2 Objects (SKIPPED)"
  warn "To run later: snow sql -f 06_phase2_optional.sql -c $CONNECTION"
else
  header "Step 6 — Phase 2 Objects (OPTIONAL)"
  warn "CORTEX.SENTIMENT on ~120K rows — may take 10–20 min."
  warn "Skip with: SKIP_PHASE2=1 ./run_all.sh $CONNECTION"
  echo ""
  run_script "06_phase2_optional.sql" \
    "Phase 2: sentiment, GEO, brand voice" "10-20 min"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║  Setup complete!                         ║"
echo -e "╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "Next steps:"
echo "  1. Wait ~5 min for Cortex Search to finish indexing"
echo "  2. Grant OAuth integration (if needed):"
echo "     snow sql -c $CONNECTION -q \"GRANT USAGE ON INTEGRATION WRITER_OAUTH TO ROLE WRITER_MARKETING_ROLE\""
echo "  3. Before each demo: snow sql -f 99_demo_reset.sql -c $CONNECTION"
echo ""
echo "Log: $LOG_FILE  |  Issues: SETUP_NOTES.md"
