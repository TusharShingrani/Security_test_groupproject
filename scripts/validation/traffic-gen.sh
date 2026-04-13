#!/usr/bin/env bash
# traffic-gen.sh — Generate synthetic traffic to trigger MC-05 / abnormal-traffic alert
#
# Sends repeated GET requests to the Gitea login page at a configurable rate.
# The alert-abnormal-traffic rule fires at >500 req/min.
#
# Usage:
#   ./traffic-gen.sh [BASE_URL] [REQUESTS] [CONCURRENCY]
#
# Defaults:
#   BASE_URL    = live Gitea URL
#   REQUESTS    = 600  (enough to exceed the 500/min threshold)
#   CONCURRENCY = 10

set -euo pipefail

BASE="${1:-https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io}"
TOTAL="${2:-600}"
CONCURRENCY="${3:-10}"
TARGET="${BASE}/user/login"

echo "=== Traffic Generator (MC-05 / abnormal-traffic alert) ==="
echo "Target     : ${TARGET}"
echo "Requests   : ${TOTAL}"
echo "Concurrency: ${CONCURRENCY}"
echo ""

# Prefer ab (Apache Bench), fallback to curl loop
if command -v ab &>/dev/null; then
  echo "Using Apache Bench (ab)..."
  ab -n "${TOTAL}" -c "${CONCURRENCY}" "${TARGET}/"
elif command -v hey &>/dev/null; then
  echo "Using hey..."
  hey -n "${TOTAL}" -c "${CONCURRENCY}" "${TARGET}"
else
  echo "ab and hey not found — using curl loop (slower, serial)"
  echo "Install apache2-utils for better load testing: sudo apt install apache2-utils"
  echo ""
  sent=0
  while [ "${sent}" -lt "${TOTAL}" ]; do
    curl -s -o /dev/null --max-time 5 "${TARGET}" &
    sent=$((sent + 1))
    # Limit background jobs to CONCURRENCY
    if [ $((sent % CONCURRENCY)) -eq 0 ]; then
      wait
    fi
  done
  wait
  echo "Sent ${sent} requests."
fi

echo ""
echo "=== Done ==="
echo "Wait 1–2 minutes then check Azure Monitor for alert-abnormal-traffic."
echo "KQL to verify:"
echo "  ContainerAppConsoleLogs_CL"
echo "  | where ContainerAppName_s == \"ca-gitea\""
echo "  | summarize RequestCount = count() by bin(TimeGenerated, 1m)"
echo "  | where RequestCount > 200"
echo "  | render timechart"
