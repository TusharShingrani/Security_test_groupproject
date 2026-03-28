# ─── WSS Certificate (self-signed, PoC only) ─────────────────────────────────
# Terraform generates a server key + self-signed cert.
# The cert is injected into all three VMs via cloud-init:
#   - Agent VM:          server key + cert (to terminate TLS)
#   - DT & Attacker VMs: cert only (to verify the server)
#
# This proves WSS is working.  Client authentication is deliberately absent
# in AUTH_MODE=none to demonstrate the vulnerability.

resource "tls_private_key" "agent_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "agent_server" {
  private_key_pem = tls_private_key.agent_server.private_key_pem

  subject {
    common_name  = "agent-vm"
    organization = "WSS-PoC"
  }

  # Valid for 30 days – enough for any PoC lifecycle.
  validity_period_hours = 720

  # The cert must cover the private IP so TLS hostname verification works.
  ip_addresses = ["10.0.1.20"]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}
