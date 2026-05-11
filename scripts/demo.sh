#!/usr/bin/env bash
# WSS Unauthorized Client Demo Script
# Usage: ./scripts/demo.sh [command]
#
# Commands:
#   status          - Check all VM services
#   connectivity    - Test network reachability between all 3 VMs
#   ssh-key         - Print the SSH key and connection instructions for teammates
#   logs-agent      - Tail agent log (shows all incoming commands)
#   logs-twin       - Tail twin log
#   attack-once     - Run attacker a single time (Phase A)
#   attack-loop     - Run attacker in a loop (Phase A, sustained)
#   phase-b-on      - Switch to AUTH_MODE=token on all VMs (show the fix)
#   phase-c-on      - Switch to AUTH_MODE=mtls on all VMs (mTLS — Phase C)
#   phase-a-on      - Switch back to AUTH_MODE=none (show the vulnerability again)
#   fix-twin        - Manually deploy files to twin-vm (if cloud-init failed)
#   help            - Show this message

set -e

INFRA_DIR="$(cd "$(dirname "$0")/../infra" && pwd)"
SSH_KEY="$HOME/poc_rsa"
TWIN_IP=""
TOKEN="changeme"

# ── helpers ─────────────────────────────────────────────────────────────────

get_twin_ip() {
  TWIN_IP=$(cd "$INFRA_DIR" && terraform output -raw twin_public_ip 2>/dev/null)
  if [[ -z "$TWIN_IP" ]]; then
    echo "ERROR: Could not get twin_public_ip from terraform output." >&2
    exit 1
  fi
}

ensure_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    echo "SSH key not found at $SSH_KEY — extracting from Terraform state..."
    cd "$INFRA_DIR"
    terraform output -raw ssh_private_key_pem > "$SSH_KEY"
    chmod 600 "$SSH_KEY"
    echo "Key saved to $SSH_KEY"
  fi
}

twin_ssh() {
  ssh -q -i "$SSH_KEY" -o StrictHostKeyChecking=no azureuser@"$TWIN_IP" "$@"
}

# Jump through twin to reach private VMs (ProxyCommand with explicit key for the hop)
agent_ssh() {
  ssh -q -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    -o "ProxyCommand=ssh -q -i $SSH_KEY -o StrictHostKeyChecking=no -W %h:%p azureuser@$TWIN_IP" \
    azureuser@10.0.1.20 "$@"
}

attacker_ssh() {
  ssh -q -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    -o "ProxyCommand=ssh -q -i $SSH_KEY -o StrictHostKeyChecking=no -W %h:%p azureuser@$TWIN_IP" \
    azureuser@10.0.1.30 "$@"
}

# ── commands ────────────────────────────────────────────────────────────────

cmd_status() {
  get_twin_ip; ensure_key
  echo "=== twin-vm (10.0.1.10 / $TWIN_IP) ==="
  twin_ssh "sudo systemctl is-active twin && sudo systemctl status twin --no-pager -l | tail -5"

  echo ""
  echo "=== agent-vm (10.0.1.20) ==="
  agent_ssh "sudo systemctl is-active agent && sudo systemctl status agent --no-pager -l | tail -5"

  echo ""
  echo "=== attacker-vm (10.0.1.30) ==="
  attacker_ssh "sudo systemctl is-active attacker 2>/dev/null || echo 'attacker service not running (expected)'"
}

cmd_logs_agent() {
  get_twin_ip; ensure_key
  echo "Tailing agent log — Ctrl+C to stop"
  echo "(Watch for lines with 'digital-twin' vs 'attacker' as source)"
  echo ""
  agent_ssh "sudo tail -f /var/log/p2p-demo/agent.log"
}

cmd_logs_twin() {
  get_twin_ip; ensure_key
  echo "Tailing twin log — Ctrl+C to stop"
  twin_ssh "sudo tail -f /var/log/p2p-demo/twin.log"
}

cmd_attack_once() {
  get_twin_ip; ensure_key
  echo ">>> Running attacker ONCE (no token, AUTH_MODE=none should accept this)"
  attacker_ssh "sudo /opt/p2p-demo/venv/bin/python3 /opt/p2p-demo/attacker.py --once"
}

cmd_attack_loop() {
  get_twin_ip; ensure_key
  echo ">>> Running attacker in LOOP — Ctrl+C to stop"
  attacker_ssh "sudo /opt/p2p-demo/venv/bin/python3 /opt/p2p-demo/attacker.py --loop"
}

cmd_phase_b_on() {
  get_twin_ip; ensure_key
  echo ">>> Enabling AUTH_MODE=token on agent and twin (Phase B — the fix)"

  agent_ssh "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=token/' /opt/p2p-demo/agent.env && sudo systemctl restart agent && echo 'agent restarted'"
  twin_ssh  "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=token/' /opt/p2p-demo/twin.env && sudo systemctl restart twin && echo 'twin restarted'"

  echo ""
  echo "Done. Legitimate twin uses token '$TOKEN' — attacker has no token and will be rejected."
  echo "Run: ./demo.sh attack-once   # to prove attacker is now blocked"
  echo "Run: ./demo.sh logs-agent    # to watch the agent reject the attack"
}

cmd_phase_c_on() {
  get_twin_ip; ensure_key
  echo ">>> Enabling AUTH_MODE=mtls on agent and twin (Phase C — mutual TLS)"
  echo "    Twin presents its client cert; attacker has no cert and is blocked at TLS handshake."

  agent_ssh "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=mtls/' /opt/p2p-demo/agent.env && sudo systemctl restart agent && echo 'agent restarted'"
  twin_ssh  "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=mtls/' /opt/p2p-demo/twin.env && sudo systemctl restart twin && echo 'twin restarted'"

  echo ""
  echo "Done. Now run the attacker to confirm it is stopped at the TLS layer:"
  echo "  ./demo.sh attack-once   # attacker gets SSL handshake error — never reaches the app"
  echo "  ./demo.sh logs-agent    # 'mTLS OK' for twin; nothing logged for attacker (rejected by SSL)"
}

cmd_phase_a_on() {
  get_twin_ip; ensure_key
  echo ">>> Reverting to AUTH_MODE=none (Phase A — vulnerability)"

  agent_ssh "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=none/' /opt/p2p-demo/agent.env && sudo systemctl restart agent && echo 'agent restarted'"
  twin_ssh  "sudo sed -i 's/^AUTH_MODE=.*/AUTH_MODE=none/' /opt/p2p-demo/twin.env && sudo systemctl restart twin && echo 'twin restarted'"

  echo "Done. All clients accepted again."
}

cmd_fix_twin() {
  get_twin_ip; ensure_key
  echo ">>> Deploying files to twin-vm manually (cloud-init recovery)"

  # Get cert from terraform
  CERT=$(cd "$INFRA_DIR" && terraform output -raw server_cert_pem 2>/dev/null)
  if [[ -z "$CERT" ]]; then
    echo "ERROR: Cannot get server_cert_pem from terraform output." >&2
    exit 1
  fi

  APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
  SVC_DIR="$(cd "$(dirname "$0")/../systemd" && pwd)"

  # Copy files
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$APP_DIR/twin.py" "$APP_DIR/requirements.txt" "$SVC_DIR/twin.service" \
    azureuser@"$TWIN_IP":/tmp/

  # Get SSH hop key
  HOP_KEY=$(cd "$INFRA_DIR" && terraform output -raw ssh_private_key_pem)

  twin_ssh "sudo bash -s" << ENDSSH
set -e
mkdir -p /opt/p2p-demo/certs /var/log/p2p-demo /home/azureuser/.ssh

mv /tmp/twin.py /opt/p2p-demo/twin.py
mv /tmp/requirements.txt /opt/p2p-demo/requirements.txt
mv /tmp/twin.service /etc/systemd/system/twin.service

cat > /opt/p2p-demo/certs/server.crt << 'CERTEOF'
${CERT}
CERTEOF

printf '%s' '${HOP_KEY}' > /home/azureuser/.ssh/poc_rsa

cat > /opt/p2p-demo/twin.env << 'ENVEOF'
AUTH_MODE=none
SCHEDULE_TOKEN=${TOKEN}
AGENT_HOST=10.0.1.20
WSS_PORT=8443
CA_CERT_PATH=/opt/p2p-demo/certs/server.crt
LOG_DIR=/var/log/p2p-demo
ENVEOF

chmod 755 /opt/p2p-demo/twin.py
chmod 644 /opt/p2p-demo/certs/server.crt
chmod 644 /etc/systemd/system/twin.service
chmod 600 /opt/p2p-demo/twin.env
chmod 600 /home/azureuser/.ssh/poc_rsa
chown azureuser:azureuser /home/azureuser/.ssh /home/azureuser/.ssh/poc_rsa
chmod 700 /home/azureuser/.ssh

python3 -m venv /opt/p2p-demo/venv
/opt/p2p-demo/venv/bin/pip install --quiet -r /opt/p2p-demo/requirements.txt
systemctl daemon-reload
systemctl enable twin
systemctl restart twin
systemctl status twin --no-pager
ENDSSH
  echo "twin-vm fixed."
}

cmd_connectivity() {
  get_twin_ip; ensure_key
  echo "=== Connectivity check across all 3 VMs ==="
  echo ""

  echo "--- twin-vm → agent-vm (10.0.1.20) ---"
  twin_ssh "ping -c 3 10.0.1.20 && echo 'ping OK' || echo 'ping FAILED'"
  echo ""
  twin_ssh "nc -zv 10.0.1.20 8443 2>&1 && echo 'WSS port 8443 OPEN' || echo 'port 8443 UNREACHABLE'"
  echo ""

  echo "--- twin-vm → attacker-vm (10.0.1.30) ---"
  twin_ssh "ping -c 3 10.0.1.30 && echo 'ping OK' || echo 'ping FAILED'"
  echo ""

  echo "--- attacker-vm → agent-vm (10.0.1.20) ---"
  attacker_ssh "ping -c 3 10.0.1.20 && echo 'ping OK' || echo 'ping FAILED'"
  echo ""
  attacker_ssh "nc -zv 10.0.1.20 8443 2>&1 && echo 'WSS port 8443 OPEN (attacker can reach agent)' || echo 'port 8443 UNREACHABLE'"
  echo ""

  echo "--- agent-vm active WSS connections ---"
  agent_ssh "sudo ss -tnp | grep 8443 || echo 'no active connections right now'"
}

cmd_ssh_key() {
  ensure_key
  echo "======================================================"
  echo " SSH KEY — share with teammates for lab access"
  echo "======================================================"
  echo ""
  echo "Only twin-vm has a public IP: $( cd "$INFRA_DIR" && terraform output -raw twin_public_ip 2>/dev/null || echo "4.235.104.66 (check terraform output)" )"
  echo "Agent-vm and attacker-vm are private — hop through twin."
  echo ""
  echo "--- Steps for your teammate ---"
  echo "1. Save the key below to ~/poc_rsa on their machine and run: chmod 600 ~/poc_rsa"
  echo "2. SSH to twin-vm:"
  echo "     ssh -i ~/poc_rsa azureuser@TWIN_IP"
  echo "3. SSH to agent-vm (via twin):"
  echo "     ssh -i ~/poc_rsa -o 'ProxyCommand=ssh -i ~/poc_rsa -W %h:%p azureuser@TWIN_IP' azureuser@10.0.1.20"
  echo "4. SSH to attacker-vm (via twin):"
  echo "     ssh -i ~/poc_rsa -o 'ProxyCommand=ssh -i ~/poc_rsa -W %h:%p azureuser@TWIN_IP' azureuser@10.0.1.30"
  echo ""
  echo "--- Private key (copy everything between the dashes) ---"
  cat "$SSH_KEY"
}

cmd_help() {
  head -16 "$0" | grep '#' | sed 's/^# //'
}

# ── dispatch ────────────────────────────────────────────────────────────────

case "${1:-help}" in
  status)          cmd_status ;;
  connectivity)    cmd_connectivity ;;
  ssh-key)         cmd_ssh_key ;;
  logs-agent)      cmd_logs_agent ;;
  logs-twin)       cmd_logs_twin ;;
  attack-once)     cmd_attack_once ;;
  attack-loop)     cmd_attack_loop ;;
  phase-b-on)      cmd_phase_b_on ;;
  phase-c-on)      cmd_phase_c_on ;;
  phase-a-on)      cmd_phase_a_on ;;
  fix-twin)        cmd_fix_twin ;;
  help|*)          cmd_help ;;
esac
