#!/usr/bin/env bash
# run-zap-baseline.sh — OWASP ZAP baseline DAST scan against the live Gitea instance
#
# Usage:
#   ./run-zap-baseline.sh [TARGET_URL]
#
# Default target: https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io
#
# Requirements: Docker (running)
# Output: zap-report.html + zap-report.json in the current directory

set -euo pipefail

TARGET="${1:-https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io}"
REPORT_DIR="$(pwd)/zap-reports"
CONTAINER="ghcr.io/zaproxy/zaproxy:stable"

echo "=== OWASP ZAP Baseline Scan ==="
echo "Target : ${TARGET}"
echo "Reports: ${REPORT_DIR}"
echo ""

mkdir -p "${REPORT_DIR}"

# Baseline scan:
#  -t  target URL
#  -r  HTML report filename (written inside container at /zap/wrk/)
#  -J  JSON report filename
#  -I  do NOT fail on warn-level alerts (only fail on FAIL-level rules)
#  -j  use Ajax spider (handles SPAs / redirects)
#  -z  pass additional ZAP CLI args (increase timeout for Container Apps cold start)
docker run --rm \
  -v "${REPORT_DIR}:/zap/wrk/:rw" \
  "${CONTAINER}" \
  zap-baseline.py \
    -t "${TARGET}" \
    -r zap-report.html \
    -J zap-report.json \
    -I \
    -j \
    -z "-config replacer.full_list(0).description=auth \
        -config replacer.full_list(0).enabled=true \
        -config replacer.full_list(0).matchtype=REQ_HEADER \
        -config replacer.full_list(0).matchstr=X-ZAP-Scan \
        -config replacer.full_list(0).replacement=true"

echo ""
echo "=== Scan complete ==="
echo "HTML report : ${REPORT_DIR}/zap-report.html"
echo "JSON report : ${REPORT_DIR}/zap-report.json"
