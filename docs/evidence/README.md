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
│   ├── screenshot-registration-blocked.png
│   └── screenshot-require-signin.png
├── phase2-brute-force/
│   ├── screenshot-rate-limit.png
│   └── screenshot-alert-fired.png
├── phase3-privilege-escalation/
│   ├── screenshot-admin-403.png
│   └── log-access-denied.txt
├── phase4-secret-leakage/
│   ├── screenshot-gitleaks-fail.png
│   └── pipeline-run-url.txt
├── phase5-insecure-terraform/
│   ├── screenshot-checkov-fail.png
│   └── checkov-output.txt
├── phase6-container-vulnerabilities/
│   ├── trivy-scan-output.txt
│   └── screenshot-pipeline-block.png
└── phase7-monitoring/
    ├── screenshot-log-analytics-query.png
    ├── screenshot-alert-rules.png
    └── kql-results.txt
```

## Validation Checklist

### Pipeline Gates
- [ ] MC-04: Gitleaks blocked a commit containing a fake secret
- [ ] MC-05: Checkov blocked an insecure Terraform change (e.g. `soft_fail: true`)
- [ ] MC-06: Trivy scan output captured showing CVEs found / ignored

### Access Controls
- [ ] MC-01: Unauthenticated access redirects to login (`REQUIRE_SIGNIN_VIEW=true`)
- [ ] MC-01: Registration page returns 403 / is not accessible (`DISABLE_REGISTRATION=true`)
- [ ] MC-03: Non-admin user cannot access `/admin` (returns 403)

### Monitoring
- [ ] KQL query `ContainerAppConsoleLogs_CL` returns Gitea log entries
- [ ] All 4 alert rules visible and enabled in Azure Monitor
- [ ] MC-02: Failed login alert fires after ≥5 failed attempts in 5 min

### Infrastructure
- [ ] `terraform output gitea_url` returns live HTTPS URL
- [ ] Key Vault secrets accessible only via managed identity (no plaintext in config)
- [ ] Container App uses `latest-rootless` image (UID 1000, non-root)
- [ ] Pipeline deploy job authenticates via OIDC (no stored client secret)

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
