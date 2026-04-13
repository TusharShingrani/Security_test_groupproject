# Misuse Cases

## MC-01: Unauthorized Access

**Actor:** External attacker  
**Goal:** Access Gitea without valid credentials

**Attack path:**
1. Attacker navigates to the Gitea URL
2. Attempts to view repositories without logging in
3. Attempts to register a new account to gain access

**Controls in place:**
- WAF sidecar (ModSecurity + OWASP CRS) — inspects every request before it reaches Gitea
- `REQUIRE_SIGNIN_VIEW=true` — all pages redirect to login; no anonymous browsing
- `DISABLE_REGISTRATION=true` — registration page returns HTTP 403
- `INSTALL_LOCK=true` — web installer is not accessible

**Expected result:**
- `GET /` → 302 redirect to `/user/login`
- `GET /user/sign_up` → 403 Forbidden

**Validation:**
```bash
./scripts/validation/check-access-controls.sh
```

Expected output: `PASS` for both MC-01a and MC-01b checks.

**Evidence:** `docs/evidence/phase1-unauthorized-access/`

---

## MC-02: Brute Force Login

**Actor:** External attacker  
**Goal:** Guess admin password via repeated login attempts

**Attack path:**
1. Attacker targets the local Gitea login form
2. Runs a password list against the `gitea-admin` account

**Controls in place:**
- Gitea rate-limits login attempts (built-in)
- `alert-failed-logins` Azure Monitor rule fires after ≥5 failed logins in 5 minutes
- TOTP MFA means even a correct password requires the second factor

**Expected result:**
- Repeated failed logins are logged by Gitea
- Azure Monitor alert fires within ~5 minutes
- MFA blocks an attacker who has guessed the password

**Validation:**
```bash
python3 scripts/validation/brute-force-sim.py
# Then wait ~5 min and check Azure Monitor → Alerts → alert-failed-logins
```

**Evidence:** `docs/evidence/phase2-brute-force/`

---

## MC-03: Privilege Escalation

**Actor:** Authenticated low-privilege user  
**Goal:** Gain admin access to Gitea

**Attack path:**
1. User authenticates via the Gitea login
2. User attempts to access the admin panel (`/-/admin/users`)
3. User attempts to modify another user's repositories

**Controls in place:**
- Gitea RBAC: only accounts with the `admin` flag can access admin routes
- `DISABLE_REGISTRATION=true` means no attacker can self-register a new account
- Admin account is created explicitly via CLI with `--admin` flag

**Expected result:**
- `GET /-/admin/users` as a non-admin → 302 redirect to login or 403
- Admin panel is inaccessible without the admin flag

**Validation:**
```bash
./scripts/validation/check-access-controls.sh
# MC-03 check tests unauthenticated access to /-/admin/users
```

**Evidence:** `docs/evidence/phase3-privilege-escalation/`

---

## MC-04: Secret Leakage via Code

**Actor:** Developer (insider threat or compromised account)  
**Goal:** Commit secrets (passwords, API keys) to the repository

**Attack path:**
1. Developer accidentally includes an `.env` file or hardcoded credential in a commit
2. Secret is pushed to the `feature/secure-cloud-platform-gitea` branch

**Controls in place:**
- Gitleaks scans every push in the GitHub Actions pipeline
- Pipeline fails immediately if any secret pattern is detected
- The commit is blocked before it can be merged or deployed

**Expected result:**
- Pipeline fails on the `gitleaks` job
- Deploy job does not run (blocked by `needs: [gitleaks, ...]`)
- Secret never reaches the repository main branch

**Validation:**
1. Create a test file containing a fake secret: `echo "FAKE_KEY=ghp_xxxxxxxxxxxxxxxxxxxx" > test-secret.txt`
2. Commit and push to the branch
3. Observe: Gitleaks job fails in GitHub Actions
4. Delete the file, push again, pipeline passes

**Evidence:** `docs/evidence/phase4-secret-leakage/`

---

## MC-05: Insecure Terraform Deployment

**Actor:** Developer or CI system  
**Goal:** Deploy infrastructure with a security misconfiguration

**Attack path:**
1. Developer writes Terraform with an insecure setting (e.g. `soft_fail = true` on Checkov,
   or `public_network_access_enabled = true` on the storage account)
2. Code is pushed and the pipeline runs

**Controls in place:**
- Checkov scans all Terraform files against CIS Azure Benchmarks
- Pipeline fails before `terraform apply` if any non-skipped check fails
- Skipped checks are documented with justification in `security.yml`

**Expected result:**
- Checkov detects the misconfiguration
- Pipeline fails on the `checkov` job
- `terraform apply` does not run

**Validation:**
1. Edit `terraform/storage.tf` to add `public_network_access_enabled = true`
2. Push to the branch — Checkov job should fail (CKV_AZURE_59 is in the skip list,
   but removing it from the skip list and enabling it would trigger a failure)
3. Alternatively: remove a justified skip from the `skip_check` list and observe Checkov fail

**Evidence:** `docs/evidence/phase5-insecure-terraform/`

---

## MC-06: Container Vulnerability Exploitation

**Actor:** External attacker  
**Goal:** Exploit a known CVE in the Gitea container image

**Attack path:**
1. Attacker identifies a CRITICAL CVE in `gitea/gitea:latest-rootless`
2. Crafts an exploit payload targeting the vulnerable component

**Controls in place:**
- WAF sidecar (ModSecurity + OWASP CRS) intercepts all HTTP requests — many CVE
  exploit payloads (path traversal, injection, malformed headers) are blocked before
  reaching Gitea
- Trivy scans the container image on every pipeline run
- Pipeline fails if any CRITICAL or HIGH unfixed CVE is found outside `.trivyignore`
- Rootless container (UID 1000) limits blast radius even if a CVE is exploited
- SSH is disabled — attack surface is limited to HTTPS port 3000 (internal), routed via WAF

**Expected result:**
- Accepted CVEs (Go stdlib requiring upstream rebuild) are in `.trivyignore`
- Any new unaccepted CRITICAL/HIGH CVE causes the `trivy` job to fail
- Deployment is blocked until the image is updated or the CVE is accepted with justification

**Validation:**
- Check the `trivy` job output in GitHub Actions — look for the scan results artifact
- Or run locally: `trivy image --ignore-file .trivyignore gitea/gitea:latest-rootless`

**Evidence:** `docs/evidence/phase6-container-vulnerabilities/`

---

## MC-07: Web Application Attack (SQLi / XSS / Injection)

**Actor:** External attacker  
**Goal:** Exploit a web application vulnerability in Gitea using common OWASP Top 10 attack patterns

**Attack path:**
1. Attacker crafts a malicious request containing a SQL injection, XSS payload, path traversal,
   Log4Shell header, or known scanner user-agent
2. Request is sent to the Gitea HTTPS endpoint

**Controls in place:**
- WAF sidecar (ModSecurity + OWASP CRS, blocking mode) sits in front of Gitea
- All incoming requests are inspected against 1000+ CRS rules before forwarding
- Matching requests are rejected with HTTP 403; Gitea never processes them
- WAF runs at PARANOIA=1 (CRS default) — low false-positive rate for normal usage

**Expected result:**
- SQLi patterns (e.g. `' OR '1'='1`) → 403 Forbidden from ModSecurity
- XSS patterns (e.g. `<script>alert(1)</script>`) → 403 Forbidden
- Path traversal (e.g. `/../../../etc/passwd`) → 403 Forbidden
- Log4Shell header (`${jndi:ldap://...}`) → 403 Forbidden
- Known scanner UA (e.g. `sqlmap`) → 403 Forbidden
- Normal browser requests → pass through to Gitea (200/302)

**Validation:**
```bash
# Test against the live WAF sidecar — no local Docker setup needed
./scripts/waf/test-waf.sh https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io
```

Expected output: all 6 attack tests show `PASS [403]`, all 3 normal tests show `PASS [200|302]`.

Check WAF block entries in Log Analytics with KQL query #9 from `docs/detections/kql-queries.md`.

**Evidence:** `docs/evidence/phase10-waf/`
