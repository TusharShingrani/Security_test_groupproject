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
    │   gitea/gitea:1.21-rootless│
    │   Port 3000 (internal)    │
    └──────┬──────────┬─────────┘
           │          │
           ▼          ▼
  ┌──────────────┐  ┌──────────────────┐
  │  Key Vault   │  │  Azure Files     │
  │  kv-gitea-xx │  │  gitea-data      │
  │              │  │  /var/lib/gitea  │
  │  - admin pw  │  │  (repos + DB)    │
  │  - secret key│  └──────────────────┘
  │  - OIDC sec  │
  └──────────────┘
        ▲
        │ managed identity (no password)
  ┌─────┴────────────┐
  │  User Assigned   │
  │  Managed Identity│
  └──────────────────┘

  ┌──────────────────┐     ┌──────────────────┐
  │  Entra ID        │     │  Log Analytics   │
  │  OIDC login      │     │  + 4 alert rules │
  └──────────────────┘     └──────────────────┘

GitHub Actions pipeline:
  Gitleaks → Checkov → Trivy → terraform validate/fmt → Deploy
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for full details.

---

## Security Controls

| Control | Tool | What it blocks |
|---|---|---|
| Zero Trust identity | Entra ID OIDC | Unauthorized access, password spray |
| Secrets management | Azure Key Vault + Managed Identity | Credential leakage |
| Container hardening | Rootless image (UID 1000) | Container escape |
| Secret scanning | Gitleaks | Secrets committed to repo |
| IaC scanning | Checkov | Insecure Terraform configs |
| Image scanning | Trivy | Vulnerable container images |
| Monitoring | Log Analytics + 4 alerts | Failed logins, restarts, anomalies |
| Registration disabled | `DISABLE_REGISTRATION=true` | Unauthorized account creation |
| Anonymous browsing blocked | `REQUIRE_SIGNIN_VIEW=true` | Unauthenticated access |

---

## Repository Structure

```
.
├── terraform/
│   ├── provider.tf       # AzureRM + random providers, remote state backend
│   ├── variables.tf      # All configurable inputs
│   ├── main.tf           # Random suffixes, data sources
│   ├── rg.tf             # Resource group (rg-gitea-sec)
│   ├── monitor.tf        # Log Analytics workspace + 4 alert rules
│   ├── identity.tf       # Managed identity + RBAC assignments
│   ├── keyvault.tf       # Key Vault + secrets
│   ├── storage.tf        # Storage account + Azure Files share
│   ├── aca.tf            # Container Apps Environment + Gitea container
│   └── outputs.tf        # Gitea URL, Key Vault name, OIDC setup guide
├── containers/
│   └── gitea/
│       └── README.md     # Container config, post-deploy setup, OIDC steps
├── docs/
│   ├── architecture/
│   │   ├── overview.md           # Full architecture diagram + trust boundaries
│   │   └── resource-assessment.md # Reuse vs new resource decisions
│   ├── threat-model/
│   │   └── threat-model.md       # STRIDE analysis
│   ├── misuse-cases/
│   │   └── misuse-cases.md       # 6 attack scenarios with expected results
│   ├── risk-analysis/
│   │   └── risk-matrix.md        # Risk matrix with probability/impact/mitigations
│   ├── detections/
│   │   └── kql-queries.md        # 8 KQL queries for Log Analytics
│   └── evidence/
│       └── README.md             # Evidence capture checklist
└── .github/workflows/
    └── security.yml      # DevSecOps pipeline (Gitleaks, Checkov, Trivy, deploy)
```

---

## Prerequisites

- Azure subscription with Container Apps available in `norwayeast`
- GitHub repository secrets:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC)
  - `GITEA_ADMIN_PASSWORD`
  - `GITEA_OIDC_CLIENT_SECRET` (after Entra ID app registration)
- GitHub repository variables:
  - `TF_STATE_RG`, `TF_STATE_SA`, `TF_STATE_CONTAINER`

---

## Deployment

### Option A — GitHub Actions (recommended)

1. Push to `feature/secure-cloud-platform-gitea`
2. Pipeline runs automatically: Gitleaks → Checkov → Trivy → Deploy
3. All gates must pass before Terraform applies
4. Get Gitea URL from the workflow output

### Option B — Manual (WSL / Cloud Shell)

```bash
cd terraform

terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=tfstatepoc2" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=gitea-sec.tfstate"

terraform apply -var="gitea_admin_password=<your-password>"

terraform output gitea_url
```

---

## Post-Deployment Steps

1. Navigate to the Gitea URL from `terraform output gitea_url`
2. Complete the web installer — create admin account
3. Follow `terraform output entra_oidc_setup` to connect Entra ID
4. In Gitea admin panel: disable local registration, require sign-in
5. Create all users through Entra ID only

See [containers/gitea/README.md](containers/gitea/README.md) for full setup guide.

---

## Monitoring

4 alert rules deployed automatically:
1. **Container restarts** — crash-loop detection
2. **Failed login attempts** — brute force detection (≥5 failures in 15 min)
3. **Local auth attempts** — OIDC bypass detection
4. **Abnormal traffic** — DoS / scanning detection (>500 req/min)

KQL queries: [docs/detections/kql-queries.md](docs/detections/kql-queries.md)

---

## Security Validation

6 misuse cases tested and documented:

| # | Scenario | Control tested |
|---|---|---|
| MC-01 | Unauthorized access | DISABLE_REGISTRATION, REQUIRE_SIGNIN_VIEW |
| MC-02 | Brute force login | Rate limiting + alert |
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

## Cleanup

```bash
cd terraform
terraform destroy -var="gitea_admin_password=any"
```

Removes all resources in `rg-gitea-sec`. The Terraform state backend (`rg-tfstate`) is shared and not destroyed.

---

## BoK Mapping

| Topic | Implementation |
|---|---|
| Threat analysis | STRIDE model, trust boundaries |
| Misuse cases | 6 documented attack scenarios |
| Authentication | Entra ID OIDC, MFA, local login disabled |
| Cryptography | TLS 1.2+ enforced on all endpoints |
| Key management | Key Vault + managed identity (no plaintext secrets) |
| Application security | DISABLE_REGISTRATION, REQUIRE_SIGNIN_VIEW |
| System security | Rootless container (UID 1000), no SSH exposed |
| Logging/monitoring | Log Analytics, 4 alerts, 8 KQL queries |
| DevSecOps | Gitleaks + Checkov + Trivy in CI/CD pipeline |
| Laws/standards | Zero Trust (NIST SP 800-207), OWASP Top 10 |
