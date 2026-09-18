#!/usr/bin/env bash
# Runs the retailcloud API Postman collections with Newman and writes
# HTML + JSON reports per collection into reports/<run timestamp>/.
#
# Usage:
#   scripts/run-tests.sh                 # run every collection (default: all three)
#   scripts/run-tests.sh catalog         # run only Catalog CRUD + Catalog QA Gap
#   scripts/run-tests.sh console         # run only Console CRUD
#
# Target environment / credentials come from environment variables so no
# secret ever needs to be committed:
#   CATALOG_BASE_URL,  CATALOG_ACCESS_TOKEN   -> retailcloud Catalog Service API
#   CONSOLE_BASE_URL,  CONSOLE_ACCESS_TOKEN    -> retailcloud Console Service API
#
# For a local run, you can instead point at one of the committed
# environments/*.postman_environment.json files (after filling in
# access_token yourself, never committed) by setting:
#   CATALOG_ENV_FILE=environments/retailcloud_catalog_dev.postman_environment.json
#   CONSOLE_ENV_FILE=environments/retailcloud_console_uat.postman_environment.json
#
# Exit code: non-zero if any collection run fails (so CI fails the job).

set -uo pipefail

SCOPE="${1:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="reports/${TS}"
mkdir -p "$OUT_DIR"

NEWMAN="npx --no-install newman"
REPORTERS="cli,json,htmlextra"

overall_status=0
summary_lines=()

run_collection () {
  local label="$1" collection="$2" base_url="$3" access_token="$4" env_file="${5:-}"
  local slug
  slug="$(echo "$label" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')"
  local json_out="${OUT_DIR}/${slug}.report.json"
  local html_out="${OUT_DIR}/${slug}.report.html"

  echo ""
  echo "=================================================================="
  echo "Running: ${label}"
  echo "Collection: ${collection}"
  echo "=================================================================="

  local args=(run "$collection" \
    --reporters "$REPORTERS" \
    --reporter-json-export "$json_out" \
    --reporter-htmlextra-export "$html_out" \
    --reporter-htmlextra-title "retailcloud API Tests - ${label}" \
    --reporter-htmlextra-darkTheme \
    --color on)

  if [[ -n "$env_file" ]]; then
    args+=(-e "$env_file")
    if [[ -n "$access_token" ]]; then
      args+=(--env-var "access_token=${access_token}")
    fi
  else
    args+=(--env-var "base_url=${base_url}" --env-var "access_token=${access_token}")
  fi

  $NEWMAN "${args[@]}"
  local status=$?

  if [[ $status -eq 0 ]]; then
    summary_lines+=("PASS  ${label}")
  else
    summary_lines+=("FAIL  ${label}  (exit ${status}) -> ${html_out}")
    overall_status=1
  fi
  return 0
}

if [[ "$SCOPE" == "all" || "$SCOPE" == "catalog" ]]; then
  run_collection "Catalog CRUD" \
    "collections/retailcloud_catalog_crud.postman_collection.json" \
    "${CATALOG_BASE_URL:-}" "${CATALOG_ACCESS_TOKEN:-}" "${CATALOG_ENV_FILE:-}"

  run_collection "Catalog QA Gap Coverage" \
    "collections/retailcloud_catalog_qa_gap_tests.postman_collection.json" \
    "${CATALOG_BASE_URL:-}" "${CATALOG_ACCESS_TOKEN:-}" "${CATALOG_ENV_FILE:-}"
fi

if [[ "$SCOPE" == "all" || "$SCOPE" == "console" ]]; then
  run_collection "Console CRUD" \
    "collections/retailcloud_console_crud.postman_collection.json" \
    "${CONSOLE_BASE_URL:-}" "${CONSOLE_ACCESS_TOKEN:-}" "${CONSOLE_ENV_FILE:-}"
fi

echo ""
echo "=================================================================="
echo "Summary (${TS})"
echo "=================================================================="
for line in "${summary_lines[@]}"; do
  echo "$line"
done
echo ""
echo "Reports written to: ${OUT_DIR}/"

# Keep a stable "latest" pointer for easy local access / CI artifact naming.
rm -f reports/latest
ln -s "${TS}" reports/latest 2>/dev/null || cp -r "$OUT_DIR" reports/latest

exit $overall_status
