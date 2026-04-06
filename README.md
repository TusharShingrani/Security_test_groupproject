# Secure Cloud Platform — Gitea on Azure

## Project Purpose

This project demonstrates a security-first deployment of Gitea (a self-hosted Git service) on Azure Container Apps, with Zero Trust access controls, DevSecOps automation, and comprehensive monitoring.

**Research question:** How effective are Zero Trust controls and DevSecOps security automation in reducing risks in a cloud-hosted platform?

---

## Architecture

```
Internet → Azure Container Apps (HTTPS) → Gitea Container
                                               │
                              ┌────────────────┤
                              │                │
                        Key Vault         Azure Files
                     (secrets via      (persistent repos
                    managed identity)    + SQLite DB)

GitHub Actions:
  Gitleaks → Checkov → Trivy → terraform validate → Deploy
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for full diagram.

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

---

## Deployment

### Prerequisites

- Azure subscription with Container Apps available in `norwayeast`
- GitHub repository secrets:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC)
  - `GITEA_ADMIN_PASSWORD`
  - `GITEA_OIDC_CLIENT_SECRET` (after Entra ID app registration)
- GitHub repository variables:
  - `TF_STATE_RG`, `TF_STATE_SA`, `TF_STATE_CONTAINER`

### Deploy via GitHub Actions

1. Push to `feature/secure-cloud-platform-gitea`
2. All security gates run automatically (Gitleaks, Checkov, Trivy)
3. If all pass, Terraform deploys to Azure
4. Get Gitea URL from workflow output

### Deploy manually

```bash
cd terraform
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=tfstatepoc2" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=gitea-sec.tfstate"

terraform apply -var="gitea_admin_password=<your-password>"
```

---

## Post-Deployment Steps

1. Navigate to the Gitea URL (`terraform output gitea_url`)
2. Complete the web installer and create admin account
3. Set up Entra ID OIDC (`terraform output entra_oidc_setup`)
4. Disable local registration in Gitea admin panel
5. Create users via Entra ID only

---

## Security Validation

See [docs/misuse-cases/misuse-cases.md](docs/misuse-cases/misuse-cases.md) for 6 attack scenarios.
Evidence captured in [docs/evidence/](docs/evidence/).

---

## Threat Model

[docs/threat-model/threat-model.md](docs/threat-model/threat-model.md) — STRIDE analysis.

---

## Monitoring

[docs/detections/kql-queries.md](docs/detections/kql-queries.md) — 8 KQL queries.

4 alert rules deployed automatically:
1. Container restarts
2. Failed login attempts (brute force)
3. Local auth attempts (OIDC bypass)
4. Abnormal traffic (DoS / scanning)

---

## Cleanup

```bash
cd terraform
terraform destroy -var="gitea_admin_password=any"
```

---

## BoK Mapping

| Topic | Implementation |
|---|---|
| Threat analysis | STRIDE model, trust boundaries |
| Misuse cases | 6 documented attack scenarios |
| Authentication | Entra ID OIDC, MFA, local login disabled |
| Cryptography | TLS 1.2+ enforced, Key Vault RSA keys |
| Key management | Key Vault + managed identity (no password) |
| Application security | DISABLE_REGISTRATION, REQUIRE_SIGNIN_VIEW |
| System security | Rootless container, no SSH exposed |
| Logging/monitoring | Log Analytics, 4 alerts, 8 KQL queries |
| DevSecOps | Gitleaks + Checkov + Trivy in CI/CD |
| Laws/standards | Zero Trust (NIST SP 800-207), OWASP Top 10 |

---

<!-- Previous project (WSS PoC) is on branch feature/poc-wss-unauthorized-client-demo -->

## What this demonstrates

> **WSS (WebSocket Secure) encrypts the transport channel. It does NOT authenticate who is sending messages.**

If the Software Agent accepts any well-formed message without verifying the sender's identity, a malicious client on the same network can send control commands — even over an encrypted WSS connection.

| Layer | What it provides | What it does NOT provide |
|---|---|---|
| TLS/WSS | Encrypted channel, integrity | Sender identity / authorisation |
| NSG rules | Network-level filtering | Application-level authentication |
| Token auth (Phase 2) | Proves sender identity | (must be implemented explicitly) |

---

## Architecture

```
 Azure VNet 10.0.0.0/16
 ┌────────────────────────────────────────────────────────────────┐
 │  twin-vm  10.0.1.10  [public IP]                            │
 │  │  twin.py                                                 │
 │  └── WSS :8443 ──────────────────────────────► agent-vm 10.0.1.20 │
 │                                                  agent.py   │
 │  attacker-vm  10.0.1.30                          WSS server │
 │  │  attacker.py (manual)                         :8443      │
 │  └── WSS :8443 ──────────────────────────────► (same agent)  │
 │                                                              │
 │  NSG: SSH from admin CIDR → twin-vm only                    │
 │       WSS :8443 open within VNet only                       │
 └────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Azure subscription (`bb1cb633-bb7e-44c4-b709-189e1cceee7e`)
- GitHub repository with Actions enabled
- Azure App Registration with Federated OIDC credential (see setup below)
- Azure Storage Account for Terraform state

---

## One-time Azure OIDC setup

```bash
# 1. Create App Registration
az ad app create --display-name "wss-poc-github-oidc"
APP_ID=$(az ad app list --display-name wss-poc-github-oidc --query '[0].appId' -o tsv)

# 2. Create Service Principal
az ad sp create --id $APP_ID

# 3. Grant Contributor on the subscription
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/bb1cb633-bb7e-44c4-b709-189e1cceee7e

# 4. Add Federated Credential (replace ORG/REPO)
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-actions-poc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:tusharshingrani/security_test_groupproject:ref:refs/heads/feature/poc-wss-unauthorized-client-demo",
  "audiences": ["api://AzureADTokenExchange"]
}'

# 5. Get values for GitHub Secrets
echo "AZURE_CLIENT_ID: $APP_ID"
echo "AZURE_TENANT_ID: $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID: $(az account show --query id -o tsv)"
```

---

## GitHub Secrets and Variables

Go to **Settings → Secrets and variables → Actions**

### Secrets (encrypted)

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | App Registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `SCHEDULE_TOKEN` | Any string, e.g. `my-secret-token` (token mode only) |

### Variables (plain text)

| Name | Example |
|---|---|
| `TF_STATE_RG` | `rg-tfstate` |
| `TF_STATE_SA` | `tfstatepoc123` |
| `TF_STATE_CONTAINER` | `tfstate` |
| `TF_STATE_KEY` | `wss-poc.tfstate` |
| `ADMIN_CIDR` | `0.0.0.0/0` (restrict to your IP) |
| `AUTH_MODE` | `none` |

---

## Deployment

### Option A — GitHub Actions (automated)

1. Push to or trigger the `feature/poc-wss-unauthorized-client-demo` branch
2. Go to **Actions → Terraform Deploy**
3. The workflow runs: Init → Validate → Plan → Apply
4. After apply, check the **Terraform Outputs** step for the Digital Twin public IP

### Option B — Azure Cloud Shell (manual, fastest)

```bash
# Open https://shell.azure.com

git clone https://github.com/tusharshingrani/security_test_groupproject
cd security_test_groupproject
git checkout feature/poc-wss-unauthorized-client-demo

# Create tfstate storage (one-time)
az group create -n rg-tfstate -l eastus
SA_NAME="tfstate$(openssl rand -hex 4)"
az storage account create -n $SA_NAME -g rg-tfstate -l eastus --sku Standard_LRS
az storage container create -n tfstate --account-name $SA_NAME

# Deploy
cd infra
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=$SA_NAME" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=wss-poc.tfstate"

terraform apply \
  -var="admin_cidr=$(curl -s ifconfig.me)/32" \
  -var="auth_mode=none" \
  -var="schedule_token=changeme"

# Get SSH access
terraform output -raw ssh_private_key_pem > ~/poc_rsa && chmod 600 ~/poc_rsa
terraform output twin_public_ip
```

### SSH access

```bash
# Into the Digital Twin (only public VM)
ssh -i ~/poc_rsa azureuser@<twin_public_ip>

# Hop to Agent from the Digital Twin
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.20

# Hop to Attacker from the Digital Twin
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.30
```

---

## Demo steps

### Phase 1 — Insecure (AUTH_MODE=none)

**Step 1: Confirm the Twin is running**

```bash
# On twin-vm
sudo tail -f /var/log/p2p-demo/twin.log
```

Expected:
```
Sent: {'source': 'digital-twin', 'electrolyzer_enable': True}
Response: {'status': 'accepted'}
```

**Step 2: Check the Agent accepts the Twin**

```bash
# On agent-vm (hop from twin-vm)
sudo tail -f /var/log/p2p-demo/agent.log
```

Expected:
```
AUTH_MODE=none: accepting from 10.0.1.10 (source=digital-twin) with NO authentication
ACCEPTED [10.0.1.10] source=digital-twin electrolyzer_enable=True
PLC state -> RUNNING (source=digital-twin)
```

**Step 3: Run the attacker**

```bash
# On attacker-vm (hop from twin-vm)
set -a; source /opt/p2p-demo/attacker.env; set +a
python3 /opt/p2p-demo/attacker.py --once
```

**Step 4: Agent log shows attacker also accepted**

```
AUTH_MODE=none: accepting from 10.0.1.30 (source=attacker) with NO authentication
ACCEPTED [10.0.1.30] source=attacker electrolyzer_enable=False
PLC state -> IDLE (source=attacker)
```

**Step 5: PLC state has been flipped**

```bash
# On agent-vm
cat /var/lib/p2p-demo/plc_state.json
```

```json
{
  "plc_state": "IDLE",
  "electrolyzer_enable": false,
  "last_source": "attacker"
}
```

**Finding confirmed: attacker changed PLC state despite WSS being active.**

---

### Phase 2 — Secure (AUTH_MODE=token)

**Option A — Redeploy via workflow/CLI:**

```bash
terraform apply -var="auth_mode=token" -var="schedule_token=my-secret-token" -auto-approve
```

**Option B — Restart services manually (faster for live demo):**

```bash
# On agent-vm
sudo sed -i 's/AUTH_MODE=none/AUTH_MODE=token/' /opt/p2p-demo/agent.env
sudo systemctl restart agent

# On twin-vm
sudo sed -i 's/AUTH_MODE=none/AUTH_MODE=token/' /opt/p2p-demo/twin.env
sudo systemctl restart twin
```

**Now run the attacker again:**

```bash
python3 /opt/p2p-demo/attacker.py --once
```

Attacker log:
```
Attack BLOCKED - reason: invalid or missing token
Fix is working: AUTH_MODE=token rejected the attacker.
```

Agent log:
```
REJECTED [10.0.1.30] source=attacker -- AUTH_MODE=token: invalid/missing token
```

Twin continues to be accepted. PLC stays RUNNING.

---

## Cleanup

**Destroy immediately after the demo to avoid unnecessary charges.**

```bash
cd infra
terraform destroy -auto-approve
```

Or delete the entire resource group from the Azure portal:
**Resource groups → rg-wss-poc → Delete**

Estimated cost: ~$0.05/hour for 3 × Standard_B1s VMs. Keep the lab running only during the demo.

---

## File structure

```
.
├── .github/workflows/
│   └── terraform-deploy.yml  # GitHub Actions pipeline (OIDC auth)
├── infra/
│   ├── main.tf               # Resource group, SSH key, Terraform config
│   ├── providers.tf          # AzureRM + TLS providers
│   ├── variables.tf          # All inputs
│   ├── network.tf            # VNet, subnet, NICs, public IPs
│   ├── nsg.tf                # NSG rules
│   ├── certs.tf              # Self-signed WSS cert
│   ├── compute.tf            # 3 VMs + cloud-init
│   ├── outputs.tf            # IPs, SSH command
│   └── cloud-init/
│       ├── agent.yaml.tftpl
│       ├── twin.yaml.tftpl
│       └── attacker.yaml.tftpl
├── app/
│   ├── agent.py              # WSS server (vulnerability + fix)
│   ├── twin.py               # Legitimate WSS client
│   ├── attacker.py           # Malicious WSS client
│   └── requirements.txt
├── systemd/
│   ├── agent.service
│   ├── twin.service
│   └── attacker.service      # Installed but NOT enabled
└── README.md
```
