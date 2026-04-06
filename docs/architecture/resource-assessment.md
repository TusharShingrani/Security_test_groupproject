# Resource Assessment — Reuse vs New

## Existing Resources (from wss-poc project)

| Resource | Name | Reuse Decision | Reason |
|---|---|---|---|
| Terraform state backend | `tfstatepoc2` SA / `rg-tfstate` RG | **Reuse** | Same SA, different state key (`gitea-sec.tfstate`) |
| Azure Subscription | `bb1cb633-bb7e-44c4-b709-189e1cceee7e` | **Reuse** | Same subscription |
| Region | `norwayeast` | **Reuse** | Cheapest available, Container Apps supported |
| GitHub OIDC credentials | `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` | **Reuse** | Same secrets in GitHub repo |
| Resource Group `rg-wss-poc` | VM-based RG | **Not reused** | Tied to VM project, clean separation needed |
| VNet `vnet-wss-poc` | 10.0.0.0/16 | **Not reused** | Container Apps uses managed VNet injection; separate concerns |
| VMs (twin/agent/attacker) | 3x Standard_B2ats_v2 | **Not reused** | Different project entirely |

## New Resources (this project)

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-gitea-sec` | All new project resources |
| Log Analytics Workspace | `law-gitea-sec` | Container logs + alert monitoring |
| User Assigned Identity | `id-gitea-sec` | Managed identity for Key Vault access |
| Key Vault | `kv-gitea-<random>` | Secrets (admin password, OIDC secret) |
| Storage Account | `sagitea<random>` | Azure Files for Gitea persistence |
| File Share | `gitea-data` | Mounted into Gitea container |
| Container Apps Environment | `cae-gitea-sec` | Managed container runtime |
| Container App | `ca-gitea` | Gitea application |

## Cost Estimate

| Resource | Tier | Est. Cost/month |
|---|---|---|
| Container Apps (Consumption) | Pay-per-use, 0.5vCPU/1Gi | ~$5-15 |
| Storage Account (LRS) | Standard | ~$1 |
| Log Analytics | Pay-per-GB (first 5GB free) | ~$0-2 |
| Key Vault | Standard (10k ops free) | ~$0 |
| **Total** | | **~$6-18/month** |
