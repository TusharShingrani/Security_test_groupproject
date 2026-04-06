# Misuse Cases

## MC-01: Unauthorized Access

**Actor:** External attacker
**Goal:** Access Gitea without valid credentials

**Attack path:**
1. Attacker navigates to Gitea URL
2. Attempts to view repositories without login
3. Attempts to register a new account

**Expected result:**
- `REQUIRE_SIGNIN_VIEW=true` — all pages require login
- `DISABLE_REGISTRATION=true` — registration page returns 403
- Only Entra ID login is available

**Validation:** Browse to Gitea URL without session → should redirect to login

---

## MC-02: Brute Force Login

**Actor:** External attacker
**Goal:** Guess admin password via repeated login attempts

**Attack path:**
1. Attacker targets local login form (if enabled)
2. Runs password list against admin account

**Expected result:**
- Gitea rate-limits login attempts
- Failed login alert fires after 5 failures in 15 minutes
- Entra ID enforced MFA blocks even correct-password attempts

**Validation:** Run 10 rapid failed login attempts → verify alert in Log Analytics

---

## MC-03: Privilege Escalation

**Actor:** Authenticated low-privilege user
**Goal:** Gain admin access to Gitea

**Attack path:**
1. User authenticates via Entra ID
2. User attempts to access /admin panel
3. User attempts to modify another user's repositories

**Expected result:**
- Gitea RBAC denies /admin to non-admin users
- Entra ID group membership controls admin role assignment

**Validation:** Login as regular user → attempt to access /admin → should return 403

---

## MC-04: Secret Leakage via Code

**Actor:** Developer (insider threat or compromised account)
**Goal:** Commit secrets (passwords, API keys) to repository

**Attack path:**
1. Developer accidentally commits `.env` file or hardcoded credential
2. Secret is pushed to Gitea

**Expected result:**
- Gitleaks scans every push in GitHub Actions pipeline
- Pipeline fails if any secret pattern is detected
- Secret never reaches the repository

**Validation:** Commit a file containing a fake AWS key → pipeline should fail

---

## MC-05: Insecure Terraform Deployment

**Actor:** Developer / CI system
**Goal:** Deploy infrastructure with security misconfigurations

**Attack path:**
1. Developer writes Terraform with open NSG rule or public storage
2. Code is pushed and pipeline runs

**Expected result:**
- Checkov detects misconfiguration
- Pipeline fails before `terraform apply`
- Misconfiguration never reaches Azure

**Validation:** Add `public_network_access_enabled = true` to storage account → Checkov should fail

---

## MC-06: Container Vulnerability Exploitation

**Actor:** External attacker
**Goal:** Exploit a known CVE in the Gitea container

**Attack path:**
1. Attacker identifies a CRITICAL CVE in the container image
2. Attacker crafts exploit payload

**Expected result:**
- Trivy scan detects CRITICAL/HIGH CVEs before deployment
- Pipeline blocks deployment of vulnerable image
- Rootless container limits blast radius even if exploited

**Validation:** Point Trivy at an outdated Gitea image → should fail pipeline
