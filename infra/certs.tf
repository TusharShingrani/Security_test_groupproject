# ── Certificate Authority ─────────────────────────────────────────────────────
# All certs (server + client) are signed by this shared CA.
# Phases A and B: only server cert used (no client verification).
# Phase C (mTLS): agent requires a valid client cert signed by this CA.
#   The legitimate twin has one. The attacker does not — handshake fails.

resource "tls_private_key" "poc_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "poc_ca" {
  private_key_pem   = tls_private_key.poc_ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "WSS-PoC-CA"
    organization = "wss-poc"
  }

  validity_period_hours = 720

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ── Server certificate (signed by CA) ────────────────────────────────────────

resource "tls_private_key" "agent_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "agent_server" {
  private_key_pem = tls_private_key.agent_server.private_key_pem

  subject {
    common_name  = "agent-vm"
    organization = "wss-poc"
  }

  ip_addresses = ["10.0.1.20"]
}

resource "tls_locally_signed_cert" "agent_server" {
  cert_request_pem   = tls_cert_request.agent_server.cert_request_pem
  ca_private_key_pem = tls_private_key.poc_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.poc_ca.cert_pem

  validity_period_hours = 720

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── Twin client certificate (signed by CA) ────────────────────────────────────
# Presented by the digital-twin during the TLS handshake in mTLS mode.
# The attacker never receives this cert or its private key.

resource "tls_private_key" "twin_client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "twin_client" {
  private_key_pem = tls_private_key.twin_client.private_key_pem

  subject {
    common_name  = "digital-twin"
    organization = "wss-poc"
  }
}

resource "tls_locally_signed_cert" "twin_client" {
  cert_request_pem   = tls_cert_request.twin_client.cert_request_pem
  ca_private_key_pem = tls_private_key.poc_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.poc_ca.cert_pem

  validity_period_hours = 720

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}
