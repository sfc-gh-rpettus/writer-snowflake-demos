#!/bin/bash
# =============================================================================
# run_phase2.sh — Apex Athletics Content Supply Chain, OPTIONAL Phase 2
#
# Phase 2 adds sentiment scoring, GEO queries, and brand voice objects. It is
# NOT required for the Phase 1 demo or the quickstart — that path is complete
# after run_all.sh. This is a separate run on purpose.
#
# Be aware before you run it:
#   • CORTEX.SENTIMENT over ~120K rows is slow, and it times out on a MEDIUM
#     warehouse. Size up to LARGE or above first.
#   • It bills Cortex token consumption.
#
# Prerequisites:
#   • run_all.sh has already completed against the same connection
#   • Snowflake CLI installed: https://docs.snowflake.com/en/developer-guide/snowflake-cli
#
# Usage:
#   chmod +x run_phase2.sh
#   ./run_phase2.sh <your-connection>   # use named connection
#   ./run_phase2.sh                     # uses SNOW_DEFAULT_CONNECTION env var
#
# Browser auth on accounts with no SAML IdP: the client id and secret for the
# built-in SNOWFLAKE$LOCAL_APPLICATION integration are the literal string
# LOCAL_APPLICATION.
#   SNOWFLAKE_AUTHENTICATOR=OAUTH_AUTHORIZATION_CODE \
#   SNOWFLAKE_OAUTH_CLIENT_ID=LOCAL_APPLICATION \
#   SNOWFLAKE_OAUTH_CLIENT_SECRET=LOCAL_APPLICATION ./run_phase2.sh <your-connection>
# =============================================================================

set -e

CONNECTION="${1:-${SNOW_DEFAULT_CONNECTION:-default}}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPTS_DIR/phase2_$(date +%Y%m%d_%H%M%S).log"
SQL_FILE="06_phase2_optional.sql"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

header()  { echo -e "\n${BLUE}${BOLD}══ $1 ══${RESET}"; }
success() { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail()    { echo -e "  ${RED}✗${RESET} $1"; }
info()    { echo -e "  ${BOLD}→${RESET} $1"; }

echo ""
echo -e "${BOLD}Apex Athletics Content Supply Chain — Phase 2 (optional)${RESET}"
echo "Connection: $CONNECTION"
echo "Log file:   $LOG_FILE"
echo ""

if ! command -v snow &>/dev/null; then
  echo "snow CLI not found. Install from:"
  echo "  https://docs.snowflake.com/en/developer-guide/snowflake-cli"
  echo ""
  echo "Or run this script manually in Snowsight:"
  echo "  $SCRIPTS_DIR/$SQL_FILE"
  exit 1
fi

if [ ! -f "$SCRIPTS_DIR/$SQL_FILE" ]; then
  fail "$SQL_FILE not found in $SCRIPTS_DIR"
  exit 1
fi

header "Phase 2 — sentiment, GEO, brand voice  (~10-20 min)"
warn "CORTEX.SENTIMENT on ~120K rows — slow, and times out on a MEDIUM warehouse."
warn "Size the warehouse up to LARGE or above before running this."
warn "This bills Cortex token consumption."
echo ""
info "Requires run_all.sh to have completed against '$CONNECTION' first."
echo ""

info "Running $SQL_FILE ..."
if snow sql -f "$SCRIPTS_DIR/$SQL_FILE" -c "$CONNECTION" >> "$LOG_FILE" 2>&1; then
  success "Phase 2 complete"
else
  fail "Phase 2 FAILED — see $LOG_FILE"
  echo ""
  warn "A timeout here usually means the warehouse is too small. Size up and retry."
  warn "Check SETUP_NOTES.md for known issues and fixes."
  exit 1
fi

echo ""
echo -e "${GREEN}${BOLD}Phase 2 objects created.${RESET}"
echo ""
echo "Log: $LOG_FILE  |  Issues: SETUP_NOTES.md"
