# Control-to-Test Mapping

Maps every implemented security control to its test method and expected result.
Use this as a validation checklist when capturing evidence for the BoK assessment.

---

## Access Controls

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| Unauthenticated browsing blocked | `REQUIRE_SIGNIN_VIEW=true` | `scripts/validation/check-access-controls.sh` MC-01a | HTTP 302 redirect to `/user/login` | `phase1-unauthorized-access/` |
| Self-registration disabled | `DISABLE_REGISTRATION=true` | `scripts/validation/check-access-controls.sh` MC-01b | HTTP 403 on `GET /user/sign_up` | `phase1-unauthorized-access/` |
| Admin RBAC | Gitea role-based access | `scripts/validation/check-access-controls.sh` MC-03 | Non-admin gets 302/403 on `/-/admin/users` | `phase3-privilege-escalation/` |
| Install wizard locked | `INSTALL_LOCK=true` | `GET /` after deploy (no setup page) | Gitea login page, not installer | — |
| SSH disabled | `DISABLE_SSH=true`, `START_SSH_SERVER=false` | `nc -z <host> 22` or port scan | Port 22 closed / no response | — |
| HTTPS-only ingress | Container Apps managed TLS | `curl -I http://...` | Redirects to HTTPS or refuses | — |

---

## Multi-Factor Authentication

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| TOTP MFA enrollment | Gitea Settings → Security → Two-Factor | Manual: follow `docs/evidence/mfa-setup.md` | After enrollment, password alone shows TOTP prompt | `phase8-mfa/screenshot-totp-prompt.png` |
| MFA — valid code grants access | Gitea TOTP | Enter correct 6-digit code | Login succeeds | `phase8-mfa/screenshot-totp-success.png` |
| MFA — invalid code rejected | Gitea TOTP | Enter `000000` as TOTP code | "Invalid two-factor code" error | `phase8-mfa/screenshot-totp-invalid.png` |

---

## Brute-Force / Rate Limiting

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| Failed login detection | alert-failed-logins (Azure Monitor) | `python3 scripts/validation/brute-force-sim.py` | Alert fires in Azure Monitor after ≥5 failed logins in 5 min | `phase2-brute-force/screenshot-alert-fired.png` |

---

## Secrets Management

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| No plaintext secrets in config | Azure Key Vault + Managed Identity | Inspect `terraform/aca.tf` — secrets reference `key_vault_secret_id` | No password values in Terraform code or pipeline variables | — |
| Secret scanning in git history | Gitleaks pipeline gate | Push a commit containing `FAKE_API_KEY=ghp_xxxx` | Pipeline fails on Gitleaks job | `phase4-secret-leakage/screenshot-gitleaks-fail.png` |

---

## IaC Security

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| Insecure Terraform blocked | Checkov pipeline gate | Add `soft_fail = true` to `checkov` job and push | Checkov reports a new HIGH finding; pipeline fails | `phase5-insecure-terraform/screenshot-checkov-fail.png` |

---

## Container Security

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| CVE scanning | Trivy pipeline gate | Push any change that triggers the pipeline | Trivy output shows accepted CVEs (Go stdlib, in `.trivyignore`) with no CRITICAL/HIGH beyond those | `phase6-container-vulnerabilities/trivy-scan-output.txt` |
| Rootless container | `latest-rootless` image (UID 1000) | `az containerapp exec` → `id` | Output: `uid=1000 gid=1000` | — |

---

## WAF (Always-On Sidecar)

The WAF (`owasp/modsecurity-crs:nginx-alpine`) is deployed as a sidecar container
inside `ca-gitea`. It is active from the moment the Container App starts — no manual
steps required. Test it by sending attack payloads directly to the live Gitea URL.

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| ModSecurity blocking mode | `MODSEC_RULE_ENGINE=On` in `terraform/aca.tf` | `./scripts/waf/test-waf.sh https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io` | Attack payloads return 403; normal requests pass (200/302) | `phase10-waf/waf-test-output.txt` |
| WAF blocks SQLi | OWASP CRS rule 942xxx | `curl "https://.../user/login?q=1'+OR+'1'='1"` | HTTP 403 from ModSecurity | `phase10-waf/screenshot-waf-block.png` |
| WAF blocks XSS | OWASP CRS rule 941xxx | `curl "https://.../search?q=<script>alert(1)</script>"` | HTTP 403 from ModSecurity | `phase10-waf/screenshot-waf-block.png` |
| WAF blocks Log4Shell | OWASP CRS rule 932xxx | `curl -H "X-Api-Version: \${jndi:ldap://x.x/a}" https://...` | HTTP 403 from ModSecurity | `phase10-waf/screenshot-waf-block.png` |
| WAF logs in Log Analytics | ContainerAppConsoleLogs_CL, ContainerName_s=="waf" | Run KQL query #9 from `docs/detections/kql-queries.md` | ModSecurity block entries visible | `phase10-waf/screenshot-waf-block.png` |

---

## DAST

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| OWASP ZAP baseline scan | `scripts/dast/run-zap-baseline.sh` or GitHub Actions `dast.yml` (runs weekly on schedule) | Run manually: `./scripts/dast/run-zap-baseline.sh` OR check Actions → DAST — ZAP Baseline Scan | ZAP report with 0 FAIL-level alerts | `phase9-dast/zap-report.html` |

---

## Monitoring & Alerting

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| Container restart alert | alert-container-restarts (Azure Monitor) | `az containerapp revision restart ...` | Alert fires in Azure Monitor | `phase7-monitoring/screenshot-alert-rules.png` |
| Abnormal traffic alert | alert-abnormal-traffic (Azure Monitor) | `scripts/validation/traffic-gen.sh` | Alert fires at >500 req/min | `phase7-monitoring/screenshot-alert-rules.png` |
| Log Analytics query | ContainerAppConsoleLogs_CL | Run KQL query #1 from `docs/detections/kql-queries.md` | Returns Gitea log rows | `phase7-monitoring/screenshot-log-analytics-query.png` |
| All 4 alert rules visible | Azure Monitor | Azure Portal → Monitor → Alerts → Alert rules | 4 rules listed and enabled | `phase7-monitoring/screenshot-alert-rules.png` |

---

## CI/CD Security

| Control | Setting / Tool | Test Method | Expected Result | Evidence File |
|---------|---------------|-------------|-----------------|---------------|
| OIDC authentication (no stored secret) | GitHub Actions federated credential | Inspect `security.yml` deploy job — no `client-secret` parameter | Pipeline authenticates via `id-token: write` + `azure/login@v2` with OIDC only | — |
| All gates must pass before deploy | `needs: [gitleaks, terraform-checks, checkov, trivy]` | Introduce a failing check (e.g. fake secret) | Deploy job does not run until all gates pass | — |

---

## How to Use This Document

1. Work through each row in order
2. Run the listed test method
3. Capture screenshot or log output in the corresponding evidence directory
4. Tick the checkbox in `docs/evidence/README.md`
5. Commit evidence files to `docs/evidence/`
