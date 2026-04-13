# Resource Assessment — Reuse vs New

## Existing Resources (from wss-poc project)

| Resource | Name | Reuse Decision | Reason |
|---|---|---|---|
| Terraform state backend | `tfstatepoc2` SA / `rg-tfstate` RG | **Reuse** | Same SA, separate state key (`gitea-sec.tfstate`) |
| Azure Subscription | `bb1cb633-bb7e-44c4-b709-189e1cceee7e` | **Reuse** | Same subscription |
| Region | `norwayeast` | **Reuse** | Cheapest available, Container Apps supported |
| GitHub OIDC app registration | `wss-poc-github-oidc` (`fda29fdf-...`) | **Reuse** | Added new federated credential `gitea-sec-branch` for this branch |
| Resource Group `rg-wss-poc` | VM-based RG | **Not reused** | Tied to VM project, clean separation needed |
| VNet `vnet-wss-poc` | 10.0.0.0/16 | **Not reused** | Container Apps uses managed networking; separate concerns |
| VMs (twin/agent/attacker) | 3x Standard_B2ats_v2 | **Not reused** | Different project entirely |

## New Resources (this project)

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-gitea-sec` | All new project resources |
| Log Analytics Workspace | `law-gitea-sec` | Container logs + alert monitoring |
| Monitor Action Group | `ag-gitea-sec` | Alert notification target |
| Monitor Alert Rules (4) | `alert-*` (ARM deployment) | Security event detection |
| User Assigned Identity | `id-gitea-sec` | Managed identity for Key Vault access |
| Key Vault | `kv-gitea-<random>` | Secrets (admin password, secret key, OIDC) |
| Storage Account | `sagitea<random>` | Azure Files for Gitea persistence (repos, logs) |
| File Share | `gitea-data` (10 GiB) | Mounted at `/var/lib/gitea` in container |
| Container Apps Environment | `cae-gitea-sec` | Managed container runtime (Consumption plan) |
| Container App | `ca-gitea` | Two containers: WAF sidecar (`owasp/modsecurity-crs:nginx-alpine`, 0.25 vCPU / 0.5Gi) + Gitea (`latest-rootless`, 0.5 vCPU / 1Gi). 1 replica. |

## OIDC Federated Credentials (on `wss-poc-github-oidc`)

Two federated credentials exist on the shared app registration:

| Name | Subject | Branch |
|---|---|---|
| `github-actions-poc2` | `repo:...:ref:refs/heads/feature/poc-wss-unauthorized-client-demo` | WSS PoC project |
| `gitea-sec-branch` | `repo:...:ref:refs/heads/feature/secure-cloud-platform-gitea` | This project |

The `gitea-sec-branch` credential was added via Azure CLI because the Azure Portal
App Registrations page is disabled by the tenant administrator for student subscriptions:

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

## Known Azure Limitations (Student Subscription)

| Limitation | Impact | Workaround |
|---|---|---|
| App Registrations portal disabled | Can't create/edit via portal UI | Use Azure CLI (`az ad app ...`) |
| No `Microsoft.Authorization/roleAssignments/write` | Can't create RBAC role assignments | Use Key Vault access policies instead of RBAC |
| `Microsoft.App` namespace not pre-registered | Container Apps fail on first deploy | Pipeline runs `az provider register --namespace Microsoft.App` |

## Azure Files SMB Limitation

SQLite cannot be used on Azure Files (SMB) because SMB does not implement POSIX `fcntl()`
advisory locks. Gitea's database migration (`migrate: sync`) fails immediately with
"database is locked" regardless of how many replicas are running.

**Resolution:** SQLite database moved to an EmptyDir volume (local to container instance).
Azure Files continues to store git repositories, avatars, attachments, and log files.

## Cost Estimate

| Resource | Tier | Est. Cost/month |
|---|---|---|
| Container Apps — Gitea (Consumption) | Pay-per-use, 0.5 vCPU / 1 GiB | ~$5–15 |
| Container Apps — WAF sidecar (Consumption) | Pay-per-use, 0.25 vCPU / 0.5 GiB | ~$3–8 |
| Storage Account (LRS) | Standard, 10 GiB file share | ~$1 |
| Log Analytics | Pay-per-GB (first 5 GB free) | ~$0–2 |
| Key Vault | Standard (10k ops/month free) | ~$0 |
| **Total** | | **~$9–26/month** |

> The WAF sidecar runs in the same Container App replica as Gitea. Both containers
> count toward the Consumption plan billing. The WAF adds roughly 50% to the
> compute cost but provides always-on ModSecurity protection at no extra infrastructure.
