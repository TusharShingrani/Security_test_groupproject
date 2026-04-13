# Evidence Capture

After running the security validation tests, capture screenshots and logs here.

## Deployed Infrastructure

| Resource | Name | Status |
|---|---|---|
| Gitea URL | `https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io` | Live |
| Key Vault | `kv-gitea-vcqg9x` | Deployed |
| Storage Account | `sagiteavcqg9x` | Deployed |
| Log Analytics | `law-gitea-sec` | Deployed |
| Alert Rules | 4 rules (ARM deployment `gitea-monitor-alerts`) | Active |
| Container App | `ca-gitea` (revision `ca-gitea--0000003+`) | Running |

## Evidence Directory Structure

```
docs/evidence/
├── phase1-unauthorized-access/
│   ├── screenshot-registration-blocked.png   (MC-01b: 403 on /user/sign_up)
│   └── screenshot-require-signin.png         (MC-01a: redirect to /user/login)
├── phase2-brute-force/
│   ├── screenshot-rate-limit.png             (login form after failed attempts)
│   └── screenshot-alert-fired.png            (Azure Monitor alert-failed-logins)
├── phase3-privilege-escalation/
│   ├── screenshot-admin-403.png              (non-admin denied /-/admin/users)
│   └── log-access-denied.txt                 (KQL query output)
├── phase4-secret-leakage/
│   ├── screenshot-gitleaks-fail.png          (pipeline Gitleaks job failure)
│   └── pipeline-run-url.txt                  (link to failed pipeline run)
├── phase5-insecure-terraform/
│   ├── screenshot-checkov-fail.png           (pipeline Checkov job failure)
│   └── checkov-output.txt                    (Checkov findings text)
├── phase6-container-vulnerabilities/
│   ├── trivy-scan-output.txt                 (Trivy table output / accepted CVEs)
│   └── screenshot-pipeline-block.png         (Trivy job in pipeline)
├── phase7-monitoring/
│   ├── screenshot-log-analytics-query.png    (KQL query returning Gitea logs)
│   ├── screenshot-alert-rules.png            (4 rules visible and enabled)
│   └── kql-results.txt                       (pasted KQL output)
├── phase8-mfa/
│   ├── screenshot-totp-prompt.png            (MFA prompt after password entry)
│   ├── screenshot-totp-success.png           (login success with valid TOTP)
│   └── screenshot-totp-invalid.png           (rejected invalid TOTP code)
├── phase9-dast/
│   ├── zap-report.html                       (ZAP baseline full HTML report)
│   └── zap-report.json                       (ZAP baseline JSON report)
└── phase10-waf/
    ├── screenshot-waf-block.png              (ModSecurity blocking attack request)
    └── waf-test-output.txt                   (test-waf.sh pass/fail output)
```

## Validation Checklist

### Access Controls
- [ ] MC-01a: Unauthenticated `GET /` redirects to `/user/login` (`REQUIRE_SIGNIN_VIEW=true`)
- [ ] MC-01b: `GET /user/sign_up` returns 403 (`DISABLE_REGISTRATION=true`)
- [ ] MC-03: Unauthenticated `GET /-/admin/users` returns 302/403 (Gitea RBAC)

**Run:** `./scripts/validation/check-access-controls.sh`

### Brute Force / Alerting
- [ ] MC-02: Failed login alert fires after ≥5 failed attempts in 5 min
- [ ] Azure Monitor → `alert-failed-logins` shows `Fired` state

**Run:** `python3 scripts/validation/brute-force-sim.py` — then check Azure Monitor

### Pipeline Gates
- [ ] MC-04: Gitleaks blocked a commit containing a fake secret
- [ ] MC-05: Checkov blocked an insecure Terraform change
- [ ] MC-06: Trivy scan output captured showing accepted CVEs

### MFA
- [ ] TOTP enrollment complete (Settings → Security → Two-Factor Authentication)
- [ ] Password alone shows TOTP prompt (not dashboard)
- [ ] Password + valid TOTP code grants access
- [ ] Password + invalid TOTP code is rejected

**See:** `docs/evidence/mfa-setup.md` for exact steps

### DAST
- [ ] ZAP baseline scan completed against live Gitea URL
- [ ] ZAP report shows 0 FAIL-level alerts

**Run:** `./scripts/dast/run-zap-baseline.sh` (or trigger the `dast.yml` Actions workflow)

### WAF
- [ ] WAF container started and proxying to Gitea
- [ ] Normal requests pass (200/302)
- [ ] Attack payloads blocked (403): SQLi, XSS, path traversal, Log4Shell, sqlmap UA

**Run:** `cd scripts/waf && docker compose up -d && ./test-waf.sh`

### Monitoring
- [ ] KQL query `ContainerAppConsoleLogs_CL` returns Gitea log entries
- [ ] All 4 alert rules visible and enabled in Azure Monitor
- [ ] `alert-abnormal-traffic` fires after running `traffic-gen.sh`

### Infrastructure
- [ ] `terraform output gitea_url` returns live HTTPS URL
- [ ] Key Vault secrets accessible only via managed identity (no plaintext in config)
- [ ] Container App uses `latest-rootless` image (UID 1000, non-root)
- [ ] Pipeline deploy job authenticates via OIDC (no stored client secret)

---

## How to View Logs

```bash
# Live log stream
az containerapp logs show \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --type console \
  --follow

# Log Analytics query (Azure Portal → law-gitea-sec → Logs)
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| order by TimeGenerated desc
| take 50
```

See [docs/detections/kql-queries.md](../detections/kql-queries.md) for all 8 queries
and instructions on how to trigger each alert.

## How to Recreate Admin User (after container restart)

```bash
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --command /bin/sh
```
```sh
gitea admin user create --config /etc/gitea/app.ini --admin --username gitea-admin --password 'your-password' --email your@email.com --must-change-password=false
```

After recreating the admin user, re-enroll TOTP MFA (enrollment is lost with the ephemeral DB).
See `docs/evidence/mfa-setup.md`.
