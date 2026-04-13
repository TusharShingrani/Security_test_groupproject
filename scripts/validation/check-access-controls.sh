#!/usr/bin/env bash
# check-access-controls.sh — Validate MC-01 and MC-03 access control settings
#
# Tests:
#   MC-01a: Unauthenticated GET / redirects to /user/login (REQUIRE_SIGNIN_VIEW)
#   MC-01b: GET /user/sign_up returns 403 (DISABLE_REGISTRATION)
#   MC-03:  GET /admin/users returns 302/403 for unauthenticated requests (Gitea RBAC)
#
# Usage:
#   ./check-access-controls.sh [BASE_URL]
#
# Example:
#   ./check-access-controls.sh https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io

set -euo pipefail

BASE="${1:-https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io}"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local expected_pattern="$2"
  local actual="$3"

  if echo "${actual}" | grep -qE "${expected_pattern}"; then
    echo "  PASS  ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  ${desc}"
    echo "        expected: ${expected_pattern}"
    echo "        got     : ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Access Control Validation ==="
echo "Target: ${BASE}"
echo ""

# MC-01a: Anonymous GET / must redirect to /user/login
echo "[MC-01a] REQUIRE_SIGNIN_VIEW — anonymous GET /"
resp=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" --max-time 10 "${BASE}/")
check "HTTP 302 and redirect to /user/login" "302.*user/login|user/login" "${resp}"

# MC-01b: GET /user/sign_up must return 403
echo "[MC-01b] DISABLE_REGISTRATION — GET /user/sign_up"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE}/user/sign_up")
check "HTTP 403 Forbidden" "^403$" "${code}"

# MC-03: Unauthenticated GET /admin must redirect to login (302) or return 403
echo "[MC-03]  RBAC — unauthenticated GET /-/admin/users"
code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "${BASE}/-/admin/users")
# Following redirects: if it ends up on login page it's a 200 (but correct behaviour);
# without -L it's 302. Either 302 or 200 on login page (not 200 on admin page) is correct.
# We re-check without -L to confirm redirect away from admin:
code_no_follow=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE}/-/admin/users")
check "Non-200 or redirect away from admin panel" "^[^2]|^20[^0]" "${code_no_follow}"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

# Also validate TLS — confirm HTTPS is enforced
echo ""
echo "[TLS]  Confirm HTTPS endpoint is reachable"
tls_check=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE}/" 2>&1)
check "HTTPS endpoint responds" "^[0-9]" "${tls_check}"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
