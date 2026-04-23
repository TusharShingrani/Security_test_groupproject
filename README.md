# Secure Cloud Platform — Gitea on Azure

## Project Purpose

This project demonstrates a security-first deployment of Gitea (a self-hosted Git service) on Azure Container Apps, with Zero Trust access controls, DevSecOps automation, and comprehensive monitoring.

**Research question:** How effective are Zero Trust controls and DevSecOps security automation in reducing risks in a cloud-hosted platform?

**Subquestions:**
1. How does Zero Trust access control (RBAC, MFA, no self-registration) improve access security?
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
                 │ port 8080
                 ▼
    ┌────────────────────────────────────────┐
    │            ca-gitea (Container App)    │
    │                                        │
    │  ┌──────────────────────────────────┐  │
    │  │  WAF sidecar                     │  │
    │  │  owasp/modsecurity-crs:nginx-alpine│ │
    │  │  Port 8080 — OWASP CRS blocking  │  │
    │  └──────────────┬───────────────────┘  │
    │                 │ localhost:3000        │
    │                 ▼                      │
    │  ┌──────────────────────────────────┐  │
    │  │  Gitea                           │  │
    │  │  gitea/gitea:latest-rootless     │  │
    │  │  UID 1000, Port 3000 (internal)  │  │
    │  └──────┬──────────────┬────────────┘  │
    └─────────┼──────────────┼───────────────┘
              │              │
              ▼              ▼
  ┌──────────────┐  ┌──────────────────┐
  │  Key Vault   │  │  Azure Files     │
  │  kv-gitea-xx │  │  /var/lib/gitea  │
  │  - admin pw  │  │  avatars, logs   │
  │  - secret key│  │  attachments     │
  │  - OIDC sec  │  └──────────────────┘
  └──────────────┘
        ▲           ┌──────────────────┐
        │ managed   │  EmptyDir (local)│
        │ identity  │  /gitea-db       │
  ┌─────┴──────┐    │  SQLite DB       │
  │  Managed   │    │  /gitea-repos    │
  │  Identity  │    │  git repos       │
  └────────────┘    │  (ephemeral)     │
                    └──────────────────┘

  ┌──────────────────┐     ┌──────────────────┐
  │  Log Analytics   │     │  Monitor Alerts  │
  │  law-gitea-sec   │     │  4 alert rules   │
  └──────────────────┘     └──────────────────┘

GitHub Actions pipeline:
  Gitleaks → Terraform fmt/validate → Checkov → Trivy → Deploy
  (scan results saved as job artifacts — no GitHub Advanced Security required)

Manual evidence tooling (local):
  scripts/dast/       → OWASP ZAP baseline scan (Docker)
  scripts/waf/        → NGINX + ModSecurity + OWASP CRS reverse proxy (Docker)
  scripts/validation/ → access control checks, brute-force sim, traffic gen
```

> **Note:** Both the SQLite database and git repositories are stored on EmptyDir (local
> ephemeral) volumes. Azure Files uses SMB which does not support POSIX `fcntl()` locks
> (SQLite) or `chmod` (git). User accounts and git repositories are lost on container
> restart. Only avatars, attachments, and logs on Azure Files persist.

See [docs/architecture/overview.md](docs/architecture/overview.md) for full details.

---

## Security Controls

| Control | Tool / Setting | What it blocks |
|---|---|---|
| Secrets management | Azure Key Vault + Managed Identity | Credential leakage, plaintext secrets |
| Secret scanning | Gitleaks | Secrets committed to git history |
| IaC scanning | Checkov | Insecure Terraform configurations |
| Image scanning | Trivy | Vulnerable container images |
| DAST | OWASP ZAP baseline (`scripts/dast/`, `dast.yml`) | Web app vulnerabilities (SQLi, XSS, misconfig) |
| WAF | NGINX + ModSecurity + OWASP CRS (sidecar, always on) | SQLi, XSS, path traversal, known scanner patterns |
| Monitoring | Log Analytics + 4 alert rules | Failed logins, restarts, traffic spikes |
| HTTPS-only | Container Apps ingress (TLS 1.2+) | Plaintext traffic |
| Registration disabled | `DISABLE_REGISTRATION=true` | Unauthorized account creation |
| Anonymous browsing blocked | `REQUIRE_SIGNIN_VIEW=true` | Unauthenticated repository access |
| SSH disabled | `DISABLE_SSH=true` | SSH attack surface |
| Rootless container | UID 1000 | Container escape via root |
| MFA (TOTP) | Gitea built-in two-factor auth | Credential-only compromise of admin account |
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
│   └── outputs.tf        # Gitea URL, Key Vault name
├── containers/
│   └── gitea/
│       └── README.md     # Container config, admin setup, known limitations
├── scripts/
│   ├── dast/
│   │   └── run-zap-baseline.sh       # Local OWASP ZAP scan (Docker)
│   ├── validation/
│   │   ├── check-access-controls.sh  # MC-01 / MC-03 curl-based checks
│   │   ├── brute-force-sim.py        # MC-02 failed login simulation
│   │   └── traffic-gen.sh            # Abnormal traffic alert trigger
│   └── waf/
│       ├── docker-compose.yml        # NGINX + ModSecurity + OWASP CRS
│       └── test-waf.sh               # WAF validation (normal + attack payloads)
├── docs/
│   ├── architecture/
│   │   ├── overview.md            # Full architecture + trust boundaries
│   │   └── resource-assessment.md # Reuse vs new resource decisions
│   ├── threat-model/
│   │   └── threat-model.md        # STRIDE analysis
│   ├── misuse-cases/
│   │   └── misuse-cases.md        # 6 attack scenarios with expected results
│   ├── risk-analysis/
│   │   └── risk-matrix.md         # Risk matrix with probability/impact/mitigations
│   ├── detections/
│   │   └── kql-queries.md         # 8 KQL queries + alert trigger instructions
│   ├── control-test-mapping.md    # Every control → test method → expected result
│   └── evidence/
│       ├── README.md              # Evidence capture checklist
│       └── mfa-setup.md          # TOTP setup steps + test checklist
└── .github/workflows/
    ├── security.yml      # DevSecOps pipeline (Gitleaks, Checkov, Trivy, deploy)
    └── dast.yml          # DAST workflow — workflow_dispatch only
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

---

## Deployment

### Option A — GitHub Actions (recommended)

1. Push to `feature/secure-cloud-platform-gitea`
2. Pipeline runs: Gitleaks → Terraform validate → Checkov → Trivy → Deploy
3. All gates must pass before Terraform applies
4. Gitea URL printed at the end of the deploy job

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
# --container gitea is required — the app now has two containers (waf + gitea)
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --container gitea \
  --command /bin/sh
```

Inside the shell (type as a single line):
```sh
gitea admin user create --config /etc/gitea/app.ini --admin --username gitea-admin --password 'your-password' --email your@email.com --must-change-password=false
```

> Both the admin user (SQLite DB) and git repositories (EmptyDir) are lost on container
> restart and must be recreated. Only avatars, attachments, and logs on Azure Files persist.

---

## Monitoring

### Alert Rules (4)

| Alert | Trigger | Severity |
|---|---|---|
| `alert-container-restarts` | OOMKilled / CrashLoopBackOff in system logs | 2 |
| `alert-failed-logins` | ≥5 failed logins in 5 min | 2 |
| `alert-local-auth-attempt` | Local password sign-in (non-OAuth2 path) | 1 |
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

Full KQL query library + alert trigger instructions: [docs/detections/kql-queries.md](docs/detections/kql-queries.md)

---

## Security Validation

Use the scripts in `scripts/validation/` and `scripts/dast/` to generate evidence.
See [docs/control-test-mapping.md](docs/control-test-mapping.md) for the complete mapping
of every control to its test method and expected result.

### Quick reference

```bash
# MC-01 + MC-03: access control checks
./scripts/validation/check-access-controls.sh

# MC-02: trigger failed-login alert (7 wrong-password attempts)
python3 scripts/validation/brute-force-sim.py

# Abnormal traffic alert
./scripts/validation/traffic-gen.sh

# DAST baseline scan (requires Docker)
./scripts/dast/run-zap-baseline.sh

# WAF: start proxy then run attack tests
cd scripts/waf && docker compose up -d && ./test-waf.sh
```

### Misuse cases

| # | Scenario | Control tested | Test method |
|---|---|---|---|
| MC-01 | Unauthorized access | `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW` | `check-access-controls.sh` |
| MC-02 | Brute force login | Failed login alert | `brute-force-sim.py` |
| MC-03 | Privilege escalation | Gitea RBAC | `check-access-controls.sh` |
| MC-04 | Secret leakage via commit | Gitleaks pipeline gate | Push fake secret |
| MC-05 | Insecure Terraform | Checkov pipeline gate | Add bad config and push |
| MC-06 | Container CVE exploitation | Trivy pipeline gate | Check Trivy job output |
| MC-07 | Web app attack (SQLi, XSS, injection) | ModSecurity WAF sidecar | `./scripts/waf/test-waf.sh <live-url>` |

See [docs/misuse-cases/misuse-cases.md](docs/misuse-cases/misuse-cases.md)

---

## MFA

Gitea's built-in TOTP MFA can be enabled for the admin account via:
**Settings → Security → Two-Factor Authentication → Enroll**

See [docs/evidence/mfa-setup.md](docs/evidence/mfa-setup.md) for exact steps and a
three-scenario test checklist (password only / password+valid TOTP / password+invalid TOTP).

---

## Threat Model

STRIDE analysis: [docs/threat-model/threat-model.md](docs/threat-model/threat-model.md)

Risk matrix: [docs/risk-analysis/risk-matrix.md](docs/risk-analysis/risk-matrix.md)

---

## Known Limitations (PoC Trade-offs)

| Limitation | Reason | Mitigation |
|---|---|---|
| SQLite DB is ephemeral (EmptyDir) | Azure Files SMB does not support POSIX `fcntl()` locks required by SQLite | Replace with Azure Database for PostgreSQL in production |
| Git repositories are ephemeral (EmptyDir) | Azure Files SMB does not support `chmod`; git calls `chmod` unconditionally on lock files during `git init` | Use Azure NFS Files (Premium) or Azure NetApp Files in production |
| Key Vault purge protection disabled | Easier PoC teardown | Enable in production |
| Key Vault network ACLs allow all | Container Apps Consumption plan has no VNet injection | Tighten to deny + IP allowlist in production |
| No Entra ID OIDC configured | Student subscription restricts app registration creation | Use CLI (`az ad app ...`) with tenant admin; Gitea TOTP is a compensating control |
| WAF uses PARANOIA=1 (CRS default) | Higher paranoia levels increase false-positive rate | Increase to level 2–3 in production and tune exclusions as needed |

---

## Cleanup

```bash
cd terraform
terraform destroy \
  -var="gitea_admin_password=any" \
  -var="gitea_oidc_client_secret=not-configured"
```

Removes all resources in `rg-gitea-sec`. The Terraform state backend (`rg-tfstate`) is shared and not destroyed.

---

## BoK Mapping

| Topic | Implementation |
|---|---|
| Threat analysis | STRIDE model, trust boundaries, 12-item risk matrix |
| Misuse cases | 6 documented attack scenarios with validation scripts |
| Authentication | `INSTALL_LOCK=true`, `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW` |
| Multi-factor authentication | Gitea built-in TOTP (`docs/evidence/mfa-setup.md`) |
| Cryptography | TLS 1.2+ enforced on all ingress endpoints |
| Key management | Azure Key Vault + Managed Identity (no plaintext secrets anywhere) |
| Application security | Rootless container (UID 1000), SSH disabled, no self-signup |
| System security | Single replica, no SSH exposed, minimal Alpine image |
| Logging/monitoring | Log Analytics workspace, 4 alert rules, 8 KQL queries with trigger instructions |
| DevSecOps | Gitleaks + Terraform validate + Checkov + Trivy as mandatory pipeline gates |
| DAST | OWASP ZAP baseline scan (`scripts/dast/`, `dast.yml` workflow) |
| WAF | NGINX + ModSecurity + OWASP CRS blocking mode (`scripts/waf/`) |
| CI/CD security | OIDC federated credentials — no stored Azure credentials in GitHub |
| Laws/standards | Zero Trust (NIST SP 800-207), OWASP Top 10, CIS Azure Benchmarks (via Checkov) |
| Control validation | `docs/control-test-mapping.md` — every control mapped to test + expected result |
