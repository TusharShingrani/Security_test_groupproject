# Secure Cloud Platform — Gitea on Azure

## Project Purpose

This project demonstrates a security-first deployment of Gitea (a self-hosted Git service) on Azure Container Apps, with Zero Trust access controls, DevSecOps automation, and comprehensive monitoring.

**Research question:** How effective are Zero Trust controls and DevSecOps security automation in reducing risks in a cloud-hosted platform?

**Subquestions:**
1. How does Entra ID + RBAC improve access security?
2. How effective is Key Vault vs storing secrets in config?
3. How does container hardening + scanning reduce risk?
4. How effective are CI/CD security gates at blocking insecure deployments?

---

## Architecture

```
             Internet
                │
                ▼ HTTPS (TLS 1.2+)
    ┌───────────────────────────┐
    │  Azure Container Apps     │
    │  Ingress (managed)        │
    └────────────┬──────────────┘
                 │
                 ▼
    ┌───────────────────────────┐
    │   Gitea (ca-gitea)        │
    │   gitea/gitea:latest-rootless│
    │   UID 1000, Port 3000     │
    └──────┬──────────┬─────────┘
           │          │
           ▼          ▼
  ┌──────────────┐  ┌──────────────────┐
  │  Key Vault   │  │  Azure Files     │
  │  kv-gitea-xx │  │  /var/lib/gitea  │
  │              │  │  repos, avatars  │
  │  - admin pw  │  │  attachments     │
  │  - secret key│  │  logs            │
  │  - OIDC sec  │  └──────────────────┘
  └──────────────┘
        ▲           ┌──────────────────┐
        │ managed   │  EmptyDir (local)│
        │ identity  │  /gitea-db       │
  ┌─────┴──────┐    │  SQLite DB       │
  │  Managed   │    │  (ephemeral)     │
  │  Identity  │    └──────────────────┘
  └────────────┘

  ┌──────────────────┐     ┌──────────────────┐
  │  Log Analytics   │     │  Monitor Alerts  │
  │  law-gitea-sec   │     │  4 alert rules   │
  └──────────────────┘     └──────────────────┘

GitHub Actions pipeline:
  Gitleaks → Terraform fmt/validate → Checkov → Trivy → Deploy
```

> **Note:** The SQLite database is stored on an EmptyDir (local ephemeral) volume, not
> on Azure Files. Azure Files uses SMB which does not support the POSIX `fcntl()` advisory
> locks that SQLite requires. User accounts and settings are recreated after a container
> restart; git repositories on Azure Files persist across restarts.

See [docs/architecture/overview.md](docs/architecture/overview.md) for full details.

---

## Security Controls

| Control | Tool / Setting | What it blocks |
|---|---|---|
| Secrets management | Azure Key Vault + Managed Identity | Credential leakage, plaintext secrets |
| Secret scanning | Gitleaks | Secrets committed to git history |
| IaC scanning | Checkov | Insecure Terraform configurations |
| Image scanning | Trivy | Vulnerable container images |
| Monitoring | Log Analytics + 4 alert rules | Failed logins, restarts, anomalies |
| HTTPS-only | Container Apps ingress (TLS 1.2+) | Plaintext traffic |
| Registration disabled | `DISABLE_REGISTRATION=true` | Unauthorized account creation |
| Anonymous browsing blocked | `REQUIRE_SIGNIN_VIEW=true` | Unauthenticated repository access |
| SSH disabled | `DISABLE_SSH=true` | SSH attack surface |
| Rootless container | UID 1000 | Container escape via root |
| OIDC CI/CD auth | GitHub Actions federated credentials | Stored CI/CD secrets |
| Install wizard locked | `INSTALL_LOCK=true` | Unauthenticated initial setup |

---

## Repository Structure

```
.
├── terraform/
│   ├── provider.tf       # AzureRM + random providers, remote state backend
│   ├── variables.tf      # All configurable inputs (max_replicas=1 for SQLite)
│   ├── main.tf           # Random suffixes, local names, data sources
│   ├── rg.tf             # Resource group (rg-gitea-sec)
│   ├── monitor.tf        # Log Analytics workspace + 4 alert rules (ARM template)
│   ├── identity.tf       # User assigned managed identity
│   ├── keyvault.tf       # Key Vault + 3 secrets (access policies, not RBAC)
│   ├── storage.tf        # Storage account + Azure Files share (repos/logs)
│   ├── aca.tf            # Container Apps Environment + Gitea container
│   └── outputs.tf        # Gitea URL, Key Vault name, OIDC setup guide
├── containers/
│   └── gitea/
│       └── README.md     # Container config, admin setup, known limitations
├── docs/
│   ├── architecture/
│   │   ├── overview.md            # Full architecture + trust boundaries
│   │   └── resource-assessment.md # Reuse vs new resource decisions
│   ├── threat-model/
│   │   └── threat-model.md        # STRIDE analysis
│   ├── misuse-cases/
│   │   └── misuse-cases.md        # 6 attack scenarios with expected results
│   ├── risk-analysis/
│   │   └── risk-matrix.md         # Risk matrix with mitigations
│   ├── detections/
│   │   └── kql-queries.md         # 8 KQL queries for Log Analytics
│   └── evidence/
│       └── README.md              # Evidence capture checklist
└── .github/workflows/
    └── security.yml      # DevSecOps pipeline (Gitleaks, Checkov, Trivy, deploy)
```

---

## Prerequisites

### GitHub Secrets (required)

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration client ID (`fda29fdf-...`) |
| `AZURE_TENANT_ID` | Azure / Entra ID tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `GITEA_ADMIN_PASSWORD` | Admin password for Gitea (you choose) |
| `GITEA_OIDC_CLIENT_SECRET` | Set to `not-configured` if Entra ID OIDC is not configured |

### GitHub Variables (required)

| Variable | Value |
|---|---|
| `TF_STATE_RG` | Resource group containing Terraform state storage |
| `TF_STATE_SA` | Storage account name (`tfstatepoc2`) |
| `TF_STATE_CONTAINER` | Blob container name (`tfstate`) |

### Azure OIDC Federated Credential

The pipeline uses OIDC (no stored client secret). A federated credential must exist on the
`wss-poc-github-oidc` app registration with subject:
```
repo:TusharShingrani/Security_test_groupproject:ref:refs/heads/feature/secure-cloud-platform-gitea
```

Add via Azure CLI if the portal App Registrations page is blocked:
```bash
az ad app federated-credential create \
  --id fda29fdf-76ee-4c9b-b5dd-438d58ff8d6a \
  --parameters '{
    "name": "gitea-sec-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:TusharShingrani/Security_test_groupproject:ref:refs/heads/feature/secure-cloud-platform-gitea",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Azure Provider Registration

The `Microsoft.App` namespace must be registered on the subscription (done once):
```bash
az provider register --namespace Microsoft.App --wait
```

The pipeline registers it automatically via `az provider register` before Terraform runs.

---

## Deployment

### Option A — GitHub Actions (recommended)

1. Push to `feature/secure-cloud-platform-gitea`
2. Pipeline runs automatically: Gitleaks → Terraform validate → Checkov → Trivy → Deploy
3. All gates must pass before Terraform applies
4. Gitea URL is printed at the end of the deploy job

### Option B — Manual (Azure CLI / Cloud Shell)

```bash
cd terraform

terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=tfstatepoc2" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=gitea-sec.tfstate"

terraform apply \
  -var="gitea_admin_password=<your-password>" \
  -var="gitea_oidc_client_secret=not-configured"

terraform output gitea_url
```

---

## Post-Deployment — Create Admin User

`INSTALL_LOCK=true` is set, so the web installer does not appear. Create the admin account
via the Container Apps exec shell:

```bash
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --command /bin/sh
```

Then inside the shell (single line):
```sh
gitea admin user create --config /etc/gitea/app.ini --admin --username gitea-admin --password 'your-password' --email your@email.com --must-change-password=false
```

> The admin user must be recreated after a container restart because the SQLite database
> is on an ephemeral EmptyDir volume. Git repositories on Azure Files are unaffected.

---

## Monitoring

### Alert Rules (4)

| Alert | Trigger | Severity |
|---|---|---|
| `alert-container-restarts` | OOMKilled / CrashLoopBackOff in system logs | 2 |
| `alert-failed-logins` | ≥5 failed logins in 5 min | 2 |
| `alert-local-auth-attempt` | Sign-in without OAuth2 (OIDC bypass) | 1 |
| `alert-abnormal-traffic` | >500 requests/min | 2 |

### Viewing Logs

**Azure Portal → Log Analytics workspaces → `law-gitea-sec` → Logs**

Example query:
```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| order by TimeGenerated desc
| take 50
```

Full KQL query library: [docs/detections/kql-queries.md](docs/detections/kql-queries.md)

> The `ContainerAppConsoleLogs_CL` table appears 2–5 minutes after the Container App
> first sends logs to the workspace.

---

## Security Validation

6 misuse cases tested and documented:

| # | Scenario | Control tested |
|---|---|---|
| MC-01 | Unauthorized access | `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW` |
| MC-02 | Brute force login | Rate limiting + failed login alert |
| MC-03 | Privilege escalation | Gitea RBAC + Entra ID groups |
| MC-04 | Secret leakage via commit | Gitleaks pipeline gate |
| MC-05 | Insecure Terraform deployment | Checkov pipeline gate |
| MC-06 | Container vulnerability exploitation | Trivy pipeline gate |

See [docs/misuse-cases/misuse-cases.md](docs/misuse-cases/misuse-cases.md)
Evidence: [docs/evidence/README.md](docs/evidence/README.md)

---

## Threat Model

STRIDE analysis across all system components.
See [docs/threat-model/threat-model.md](docs/threat-model/threat-model.md)

Risk matrix with probability/impact/mitigations:
See [docs/risk-analysis/risk-matrix.md](docs/risk-analysis/risk-matrix.md)

---

## Known Limitations (PoC Trade-offs)

| Limitation | Reason | Mitigation |
|---|---|---|
| SQLite DB is ephemeral (EmptyDir) | Azure Files SMB does not support POSIX file locks required by SQLite | For production, replace SQLite with Azure Database for PostgreSQL |
| Key Vault purge protection disabled | Easier PoC teardown | Enable in production |
| Key Vault network ACLs allow all | Container Apps Consumption plan has no VNet injection | Tighten to deny + IP rules in production |
| No Entra ID OIDC configured | Student subscription restricts app registration creation | Configure via CLI with tenant admin assistance |

---

## Cleanup

```bash
cd terraform
terraform destroy \
  -var="gitea_admin_password=any" \
  -var="gitea_oidc_client_secret=not-configured"
```

Removes all resources in `rg-gitea-sec`. The Terraform state backend (`rg-tfstate`) is shared and is not destroyed.

---

## BoK Mapping

| Topic | Implementation |
|---|---|
| Threat analysis | STRIDE model, trust boundaries, 12-item risk matrix |
| Misuse cases | 6 documented attack scenarios with expected outcomes |
| Authentication | `INSTALL_LOCK=true`, `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW` |
| Cryptography | TLS 1.2+ enforced on all ingress endpoints |
| Key management | Azure Key Vault + Managed Identity (no plaintext secrets anywhere) |
| Application security | Rootless container (UID 1000), SSH disabled, no self-signup |
| System security | Single replica, no SSH port exposed, minimal image surface |
| Logging/monitoring | Log Analytics workspace, 4 alert rules, 8 KQL detection queries |
| DevSecOps | Gitleaks + Terraform validate + Checkov + Trivy as mandatory pipeline gates |
| CI/CD security | OIDC federated credentials — no stored Azure credentials in GitHub |
| Laws/standards | Zero Trust (NIST SP 800-207), OWASP Top 10, CIS Azure Benchmarks (via Checkov) |
