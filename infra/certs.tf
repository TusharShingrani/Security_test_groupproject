# Self-signed TLS cert for the WSS server.
# Proves transport is encrypted. Client auth is intentionally absent (Phase 1).

resource "tls_private_key" "agent_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "agent_server" {
  private_key_pem = tls_private_key.agent_server.private_key_pem

  subject {
    common_name  = "agent-vm"
    organization = "wss-poc"
  }

  validity_period_hours = 720

  # Cover the agent's static private IP for TLS verification
  ip_addresses = ["10.0.1.20"]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}
