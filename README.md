# WSS Unauthorized Client – Security PoC

## 1. What this PoC demonstrates

> **Finding:** Even when the Digital Twin and Software Agent communicate over
> **WSS (WebSocket Secure / TLS)**, a malicious client can still inject
> schedule messages if the Agent does **not authenticate or authorise the
> sender**.

### Why WSS alone is not enough

| Protection layer | What it does | What it does NOT do |
|---|---|---|
| TLS (WSS) | Encrypts data in transit, prevents eavesdropping and tampering | Does **not** verify *who* is connecting |
| IP allow-listing (NSG) | Limits which hosts can reach the port | Can be bypassed if the attacker is on the same VNet |
| Application-level auth | Proves the sender identity before acting | Must be implemented explicitly – it is **not** provided by TLS |

This lab has **two phases**:

- **Phase A (`AUTH_MODE=none`)** – Agent accepts any correctly-formed message.
  The Attacker can disable the electrolyzer even though TLS is running.
- **Phase B (`AUTH_MODE=token`)** – Agent requires a shared token.
  The Attacker is rejected; the Digital Twin is still accepted.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Azure VNet  10.0.0.0/16  (eastus)                       │
│                                                           │
│  ┌─────────────────────┐    WSS (TLS) :8443              │
│  │  dt-vm  10.0.1.10   │ ──────────────────────────►     │
│  │  Digital Twin       │                              ┌──┴──────────────────┐
│  │  twin.py            │                              │ agent-vm 10.0.1.20  │
│  │  sends every 10s    │                              │ Software Agent      │
│  │                     │   SSH hop                    │ agent.py (WSS srv)  │
│  │  [public IP]        │ ──────────────────────────►  │ AUTH_MODE=none|token│
│  └──────────────────┬──┘                              └──┬──────────────────┘
│          │ SSH       │                                    │
│          │           │   WSS (TLS) :8443                  │
│          │      ┌────▼────────────────┐                   │
│          │      │ attacker-vm 10.0.1.30│ ─────────────────►
│          │      │ Attacker             │
│          │      │ attacker.py (manual) │
│          │      └─────────────────────┘
│          │                                                 │
│  NSG: only admin CIDR reaches port 22 on dt-vm            │
│       VNet traffic allowed on :8443 and :22               │
└──────────────────────────────────────────────────────────┘
```

**Flow (Phase A – insecure):**

1. Digital Twin → Agent: `electrolyzer_enable: true` → Agent accepts → PLC: `RUNNING`
2. Attacker → Agent: `electrolyzer_enable: false` → Agent accepts → PLC: `IDLE`

**Flow (Phase B – token auth):**

1. Digital Twin → Agent: message + valid token → Agent accepts → PLC: `RUNNING`
2. Attacker → Agent: message without token → Agent **rejects** → PLC unchanged

---

## 3. Cost-saving defaults

| Decision | Reason |
|---|---|
| `Standard_B1s` VMs (1 vCPU, 1 GB RAM) | Cheapest general-purpose Linux VM in Azure; more than enough for Python WSS |
| One public IP only (Digital Twin) | Agent and Attacker are private-only; reviewer reaches them by SSH hop from the DT |
| No load balancer | Single-VM PoC; no HA needed |
| No Bastion | SSH via public IP on DT is sufficient and free |
| No Key Vault | Self-signed cert and token injected via cloud-init; acceptable for a short-lived lab |
| No managed disks / premium storage | Standard LRS OS disks cost ~$1.50/month |
| No availability zones | Single AZ; no SLA needed for a demo |
| Single region | Saves cross-region data transfer costs |

Estimated cost: **< $10/month** for all three `Standard_B1s` VMs.

Set `enable_public_ip_all = true` in the pipeline variables if you need direct
SSH to the Agent or Attacker VMs for troubleshooting (adds ~$0.004/hour per
extra Basic public IP).

---

## 4. Prerequisites

- **Azure subscription** with Contributor access
  (subscription ID: `bb1cb633-bb7e-44c4-b709-189e1cceee7e`)
- **Azure DevOps** organisation and project
- **Azure Resource Manager service connection** in the project with
  Contributor rights on the subscription
- **Terraform remote state storage** – a pre-existing storage account with:
  - a resource group (e.g. `rg-tfstate`)
  - a storage account with blob public access disabled
  - a container named e.g. `tfstate`
- **Your public IP/CIDR** for the `ADMIN_CIDR` variable so SSH is not
  open to the whole internet

---

## 5. Deployment steps

### 5.1 Create the pipeline in Azure DevOps

1. Go to **Pipelines → New pipeline → Azure Repos Git** (or GitHub)
2. Select this repository
3. Choose **Existing Azure Pipelines YAML file**
4. Path: `pipelines/azure-pipelines.yml`
5. Click **Continue** but do **not** run yet

### 5.2 Set pipeline variables

In **Variables** (or a variable group linked to the pipeline), set:

| Variable | Example value | Secret? |
|---|---|---|
| `ARM_SERVICE_CONNECTION` | `my-azure-sc` | No |
| `TF_STATE_RG` | `rg-tfstate` | No |
| `TF_STATE_SA` | `tfstatepoc123` | No |
| `TF_STATE_CONTAINER` | `tfstate` | No |
| `TF_STATE_KEY` | `wss-poc.tfstate` | No |
| `LOCATION` | `eastus` | No |
| `ADMIN_CIDR` | `203.0.113.10/32` | No |
| `AUTH_MODE` | `none` | No |
| `SCHEDULE_TOKEN` | `my-secret-token` | **Yes** |

### 5.3 Queue the pipeline

Click **Run** on the pipeline. The stages run in order:
`Validate → Plan → Apply`

After `Apply` succeeds, scroll to the **Show Terraform outputs** step to get:

```
dt_public_ip      = "x.x.x.x"
agent_private_ip  = "10.0.1.20"
attacker_private_ip = "10.0.1.30"
```

### 5.4 SSH into the Digital Twin

```bash
# Save the private key (from Terraform output)
terraform -chdir=infra output -raw ssh_private_key_pem > poc_rsa
chmod 600 poc_rsa

# Connect to the Digital Twin
ssh -i poc_rsa azureuser@<dt_public_ip>
```

### 5.5 SSH hop to private VMs

The SSH private key is automatically written to `~/.ssh/poc_rsa` on the
Digital Twin VM. From the DT, hop to the Agent or Attacker:

```bash
# From the Digital Twin VM:
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.20   # Software Agent
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.30   # Attacker VM
```

---

## 6. Demo script

### Phase A – Insecure (AUTH_MODE=none)

#### Step 1 – Confirm Digital Twin is sending

SSH to the Digital Twin VM and tail the log:

```bash
ssh -i poc_rsa azureuser@<dt_public_ip>
sudo tail -f /var/log/p2p-demo/twin.log
```

You should see entries like:

```
2025-01-01T12:00:00+00:00 [INFO] digital-twin: Sending schedule message schedule_id=abc-123
2025-01-01T12:00:00+00:00 [INFO] digital-twin: Agent response: {'status': 'accepted', ...}
```

#### Step 2 – Inspect Agent logs (Digital Twin accepted)

From the Digital Twin, hop to the Agent and check logs:

```bash
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.20
sudo tail -f /var/log/p2p-demo/agent.log
```

You should see:

```
[INFO]  Received message from 10.0.1.10 | source=digital-twin | electrolyzer_enable=True
[WARNING] AUTH_MODE=none – accepting message from 10.0.1.10 (source=digital-twin) WITHOUT any authentication
[INFO]  ACCEPTED [10.0.1.10] source=digital-twin schedule_id=abc-123 electrolyzer_enable=True
[INFO]  PLC state updated → RUNNING
```

#### Step 3 – Run the attacker one-shot script

From the Digital Twin, hop to the Attacker VM and run the attack:

```bash
ssh -i ~/.ssh/poc_rsa azureuser@10.0.1.30

# Source the env vars and run the attack
set -a; source /opt/p2p-demo/attacker.env; set +a
python3 /opt/p2p-demo/attacker.py --once
```

#### Step 4 – Inspect Agent logs (Attacker accepted)

Back on the Agent VM:

```bash
sudo tail -20 /var/log/p2p-demo/agent.log
```

You will see:

```
[INFO]  Received message from 10.0.1.30 | source=attacker | electrolyzer_enable=False
[WARNING] AUTH_MODE=none – accepting message from 10.0.1.30 (source=attacker) WITHOUT any authentication. This is the vulnerability!
[INFO]  ACCEPTED [10.0.1.30] source=attacker schedule_id=xyz-456 electrolyzer_enable=False
[INFO]  PLC state updated → IDLE
```

#### Step 5 – Inspect PLC state

```bash
cat /var/lib/p2p-demo/plc_state.json
```

```json
{
  "timestamp": "2025-01-01T12:00:05+00:00",
  "plc_state": "IDLE",
  "electrolyzer_enable": false,
  "last_source": "attacker",
  "last_schedule_id": "xyz-456"
}
```

**Finding confirmed:** The attacker flipped the electrolyzer off despite WSS
being active.

---

### Phase B – Fixed (AUTH_MODE=token)

#### Step 1 – Switch to token mode

Update the `AUTH_MODE` pipeline variable to `token` and re-queue the pipeline
(or update the env file directly):

**Option A – Re-run the pipeline:**

Change pipeline variable `AUTH_MODE` to `token`, then queue a new run.
Terraform will update the env files and restart the services via cloud-init
on a fresh `terraform apply`.

**Option B – Update and restart manually (faster for demo):**

On the Agent VM:

```bash
sudo sed -i 's/AUTH_MODE=none/AUTH_MODE=token/' /opt/p2p-demo/agent.env
sudo systemctl restart software-agent
```

On the Digital Twin VM:

```bash
sudo sed -i 's/AUTH_MODE=none/AUTH_MODE=token/' /opt/p2p-demo/twin.env
sudo systemctl restart digital-twin
```

#### Step 2 – Confirm Digital Twin is still accepted

Agent log should show:

```
[INFO]  Token validated OK for source=digital-twin
[INFO]  ACCEPTED [10.0.1.10] source=digital-twin schedule_id=... electrolyzer_enable=True
[INFO]  PLC state updated → RUNNING
```

#### Step 3 – Run the attacker again

```bash
# On attacker-vm:
python3 /opt/p2p-demo/attacker.py --once
```

#### Step 4 – Confirm Attacker is rejected

Agent log:

```
[WARNING] REJECTED [10.0.1.30] source=attacker schedule_id=... – AUTH_MODE=token: missing or invalid token
```

Attacker log:

```
[INFO] Attack BLOCKED – Agent rejected the message. reason=invalid or missing token
[INFO] This demonstrates the fix: AUTH_MODE=token is working correctly.
```

#### Step 5 – PLC state unchanged

```bash
cat /var/lib/p2p-demo/plc_state.json
# plc_state should still be RUNNING from the Digital Twin
```

---

## 7. Cleanup

**Destroy all Azure resources immediately after the demo:**

```bash
# From your local machine in the infra/ directory:
terraform destroy \
  -var="location=eastus" \
  -var="admin_cidr=0.0.0.0/0" \
  -var="auth_mode=none" \
  -var="schedule_token=changeme"

# Or via the pipeline: add a Destroy stage or run:
# terraform destroy -auto-approve
```

> **Reminder:** `Standard_B1s` VMs accrue charges while running.
> Destroy the lab immediately after use. The entire resource group
> `rg-wss-poc` can be deleted from the Azure portal as a fast alternative.

---

## 8. File structure

```
.
├── README.md
├── .gitignore
├── app/
│   ├── requirements.txt    # Python deps (websockets)
│   ├── common.py           # Shared helpers (logging, message schema)
│   ├── agent.py            # WSS server – Software Agent
│   ├── twin.py             # WSS client – Digital Twin
│   └── attacker.py         # WSS client – Attacker (manual run)
├── infra/
│   ├── versions.tf         # Provider + backend constraints
│   ├── providers.tf        # AzureRM + TLS providers
│   ├── variables.tf        # All configurable inputs
│   ├── main.tf             # Resource group, SSH key, random suffix
│   ├── network.tf          # VNet, subnet, NICs, public IPs
│   ├── nsg.tf              # NSG + rules
│   ├── certs.tf            # Self-signed TLS cert for WSS
│   ├── compute.tf          # 3 VMs + cloud-init rendering
│   ├── outputs.tf          # IPs, SSH command, SSH key
│   └── cloud-init/
│       ├── software-agent.yaml.tftpl
│       ├── digital-twin.yaml.tftpl
│       └── attacker.yaml.tftpl
├── systemd/
│   ├── software-agent.service
│   ├── digital-twin.service
│   └── attacker.service
└── pipelines/
    └── azure-pipelines.yml
```
