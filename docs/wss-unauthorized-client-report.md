# WebSocket Security — Unauthorized Client Attack & Progressive Mitigation
### Security Research Report | feature/poc-wss-mtls

---

## 1. Introduction

Modern Industrial Control Systems (ICS) increasingly rely on network-connected components that communicate over standard web protocols. This research investigates a security vulnerability in WebSocket-based machine-to-machine communication: the absence of client authentication. Using a purpose-built Proof-of-Concept (PoC) environment deployed on Azure, this report documents three progressive security layers — from unencrypted WebSockets to transport encryption (WSS) to application-layer token authentication and finally to mutual TLS (mTLS) — evaluating the attack surface at each stage.

The PoC simulates a realistic ICS scenario: a Digital Twin client sends scheduled electrolyzer commands to a Software Agent every 10 seconds. The research question is: *at what layer can an attacker inject unauthorized commands, and at what layer can this be reliably prevented?*

> **[INSERT HERE: Figure 1 — MITM attack diagram (stick figure between Digital Twin and PC with running agent, two WSS arrows)]**

---

## 2. Library Research

### 2.1 WebSocket Protocol and Security Model

The WebSocket protocol (RFC 6455) establishes a full-duplex communication channel over a single TCP connection. It is initiated via an HTTP Upgrade handshake, after which the connection is independent of HTTP. WebSocket Secure (WSS) is the TLS-encrypted equivalent — analogous to HTTPS being HTTP over TLS.

According to the IETF specification (RFC 6455, Section 10), the WebSocket protocol relies on the origin-based security model of browsers for web clients. For machine-to-machine communication, however, there is no browser enforcing origin policy — any client that can reach the server's port and speak the WebSocket protocol can establish a connection.

**What TLS gives you:**
- Encrypted wire (no eavesdropping)
- Server identity verified via certificate
- Data integrity (no tampering in transit)

**What TLS does NOT give you:**
- Proof of who the client is
- Any access control
- Application-level authentication

> **[INSERT HERE: Table 1 — "What TLS gives you vs. does not give you" (two-column table from sprint content)]**

This distinction is critical in ICS environments. The NIST Cybersecurity Framework and IEC 62443 (Industrial Automation and Control Systems Security) both emphasize that transport-layer encryption must be complemented by identity verification at the application or session layer. TLS alone satisfies confidentiality and integrity requirements but does not satisfy authentication requirements for client endpoints.

### 2.2 The Unauthorized Client Threat in ICS

MITRE ATT&CK for ICS (technique T0885 — Commonly Used Port, T0830 — Adversary-in-the-Middle) documents adversarial use of legitimate communication protocols to inject commands into industrial systems. An attacker who understands the message schema of a target ICS protocol can craft valid messages and inject them over an authenticated transport channel — because the transport authenticated the server, not the sender.

In the context of WebSockets, this means an attacker on the same network segment who knows the server address, port, and message format can connect and send arbitrary commands. The server has no mechanism to distinguish a legitimate Digital Twin from a rogue client.

### 2.3 Application-Layer Authentication — Token-Based Approach

A shared secret token embedded in the message payload is a common first-line mitigation. The server validates the token on every message and rejects those without a valid credential. OWASP recommends this approach for API security (OWASP API Security Top 10 — API2: Broken Authentication).

Limitations documented in literature:
- Tokens transmitted in application data are only protected by the transport layer. If TLS is stripped or a session is hijacked, the token is exposed.
- Shared secrets are subject to brute-force attacks if not rotated and rate-limited.
- Token leakage via logs, configuration files, or insider access immediately grants full attacker access.
- The server still processes (parses) attacker messages before rejecting them — the attack surface at the application handler remains.

### 2.4 Mutual TLS (mTLS)

Mutual TLS extends the standard TLS handshake to require both parties to present and verify certificates. Where standard TLS only verifies the server (one-way), mTLS verifies both server and client during the cryptographic handshake — before any application data is exchanged.

RFC 8446 (TLS 1.3) defines the `CertificateRequest` message, which the server sends to request a client certificate during the handshake. If the client cannot present a certificate signed by a trusted Certificate Authority (CA), the handshake is aborted at the TLS layer.

**Advantages of mTLS over application-layer alternatives:**

| Property | IP Allowlisting | Token / API Key | mTLS |
|---|---|---|---|
| Bypassed by compromised internal host | Yes | No | No |
| Secret can be leaked | N/A | Yes | No (private key never transmitted) |
| Authentication layer | Network | Application | TLS handshake |
| App handler reached on attack | Yes | Yes | No |
| Standard in zero-trust / ICS | No | Partial | Yes |

mTLS is the standard authentication mechanism in zero-trust network architectures (NIST SP 800-207), service meshes (Istio, Linkerd), IoT device authentication frameworks, and ICS security standards (IEC 62443-3-3 SR 1.2 — Software Process and Device Identification).

### 2.5 PKI for mTLS

A minimal PKI for mTLS requires:
- A root CA (self-signed certificate that signs all other certificates)
- A server certificate signed by the CA (presented by the server)
- A client certificate signed by the CA (presented by the legitimate client)

The server configures `ssl.CERT_REQUIRED` and loads the CA certificate as a trusted anchor. Any client that cannot present a CA-signed certificate is rejected at the handshake — the application layer is never reached.

> **[INSERT HERE: Figure 2 — PKI tree diagram: WSS-PoC-CA → agent-server.crt + twin-client.crt, with note "Attacker: knows CA, has NO client cert"]**

---

## 3. Lab Research

### 3.1 Environment Setup

The PoC was deployed on three Azure Virtual Machines within a single VNet (10.0.0.0/16):

| VM | IP | Role |
|---|---|---|
| Digital Twin VM | 10.0.1.10 | Legitimate WSS client, sends `electrolyzer_enable: true` every 10s |
| Software Agent VM | 10.0.1.20:8443 | WSS server, receives commands, updates PLC state |
| Attacker VM | 10.0.1.30 | Rogue WSS client, sends `electrolyzer_enable: false` |

The Software Agent supports three authentication modes controlled by the `AUTH_MODE` environment variable: `none` (Phase A), `token` (Phase B), and `mtls` (Phase C).

> **[INSERT HERE: Figure 3 — Azure VNet diagram showing three VMs with WSS arrows (from sprint 1 dark-background diagram)]**

### 3.2 Phase A — The Vulnerability (AUTH_MODE=none)

**Finding:** With WSS active (TLS encryption enabled), the agent accepts commands from any client that speaks the protocol — including the attacker.

The Digital Twin connects over WSS, and the TLS handshake verifies the server certificate. However, the server performs no reciprocal verification of the client. The agent receives two indistinguishable TLS connections:

- Digital Twin → `{"source": "digital-twin", "electrolyzer_enable": true}`
- Attacker → `{"source": "attacker", "electrolyzer_enable": false}`

Both are accepted. The attacker successfully changes the PLC state to STOPPED.

**Root cause:** TLS performs a *server* handshake only. The client verifies the server's certificate, but the server has no certificate or credential to demand from the client. From the agent's perspective, both connections are anonymous TLS clients on port 8443 — they are identical.

> **[INSERT HERE: Screenshot 1 — Terminal showing agent log with both digital-twin and attacker ACCEPTED entries side by side]**

> **[INSERT HERE: Figure 4 — Phase A sequence diagram: twin sends true (accepted), attacker sends false (also accepted)]**

This aligns with the theoretical finding in Section 2.1: WSS protects the channel, not the application. Transport encryption does not imply sender authentication.

### 3.3 Phase B — Token Authentication Fix (AUTH_MODE=token)

**Finding:** Adding a shared secret token to the JSON payload blocks the attacker — provided the token is unknown to the attacker.

The Digital Twin includes `"token": "changeme"` in every message. The agent validates this token before processing the command. The attacker, not knowing the token, is rejected at the application handler.

```
Agent log:
REJECTED [10.0.1.30] source=attacker -- AUTH_MODE=token: invalid/missing token
```

The token travels inside the encrypted TLS tunnel, so it cannot be sniffed off the wire. This represents a meaningful improvement over Phase A.

**Remaining gap:** The agent still parses the attacker's JSON payload before rejecting it. The application handler is reached on every attack attempt. If the token were to leak through logs, configuration files, or insider access, the attacker would gain immediate full access without any further barrier.

> **[INSERT HERE: Screenshot 2 — Terminal showing agent log: REJECTED for attacker, ACCEPTED for twin in Phase B]**

### 3.4 Phase C — Mutual TLS (AUTH_MODE=mtls)

**PKI deployed:**

| Artifact | Purpose |
|---|---|
| `WSS-PoC-CA` | Self-signed root CA — signs all certificates |
| `agent-server.crt` | Server certificate — presented by Software Agent, verified by all clients |
| `twin-client.crt` / `twin-client.key` | Client certificate — presented by Digital Twin at TLS handshake, verified by Agent |
| Attacker VM | Has `ca.crt` to verify the server but has **no client certificate** |

**Agent configuration:**
```python
ssl_ctx.verify_mode = ssl.CERT_REQUIRED
ssl_ctx.load_verify_locations("ca.crt")
```

**Twin configuration:**
```python
ssl_ctx.load_cert_chain(certfile="twin-client.crt", keyfile="twin-client.key")
```

**Finding — Legitimate Twin:** The Digital Twin presents `twin-client.crt` during the TLS handshake. The agent verifies the certificate is signed by the trusted CA. Handshake completes. Commands flow normally.

```
Agent log:
mTLS OK for source=digital-twin
```

**Finding — Attacker:** The attacker connects without a client certificate. The agent sends a `certificate_required` TLS alert. The connection is refused before the WebSocket upgrade, before any HTTP request, before any JSON is parsed, before any application handler is called.

```
Attacker log:
ATTACK BLOCKED at TLS layer (AUTH_MODE=mtls)
TLS rejected before HTTP upgrade — no client cert provided.
Agent requires a client certificate signed by the trusted CA.
```

**Critical observation:** The agent log contains **no entry at all** for the attacker's connection attempt. The rejection happens entirely within the TLS stack — the application is never aware the attacker tried to connect.

> **[INSERT HERE: Screenshot 3 — Three terminals: (1) agent log showing mTLS OK for twin, silence for attacker; (2) twin log showing normal operation; (3) attacker log showing ATTACK BLOCKED at TLS layer]**

> **[INSERT HERE: Figure 5 — mTLS handshake diagram (the "How mTLS works in this setup" diagram with green twin panel and red attacker panel)]**

**Note on the attacker having the CA certificate:** The attacker VM was deliberately given `ca.crt` to prove the strongest possible attacker scenario — one who can verify the server is legitimate and knows the full PKI structure. Even with this knowledge, without a CA-signed client certificate, the TLS handshake cannot complete. Knowing the server is real does not grant access.

### 3.5 Comparative Results

| Property | Phase A — No Auth | Phase B — Token | Phase C — mTLS |
|---|---|---|---|
| Wire encryption | Yes | Yes | Yes |
| Server identity verified | Yes | Yes | Yes |
| Client identity verified | **No** | App layer (token) | **TLS layer (cert)** |
| Attack blocked | **No** | Yes (if token unknown) | **Yes (always)** |
| App handler reached on attack | Yes | Yes | **No** |
| Block point | — | Application handler | TLS handshake |
| Bypassed if | — | Token leaked | CA private key stolen |

> **[INSERT HERE: Table 2 — Completed version of the above comparison table]**

---

## 4. Conclusion

This research demonstrates that transport-layer encryption alone is insufficient to secure machine-to-machine WebSocket communication in ICS environments. Three progressive findings were established:

**WSS (TLS) encrypts but does not authenticate.** Phase A showed that a fully encrypted WSS connection provides no barrier to an unauthorized client who knows the server address and message schema. Any client on the network can inject commands.

**Application-layer token authentication is a meaningful but incomplete fix.** Phase B blocked the attack under normal conditions but leaves the application handler exposed on every attack attempt and relies on a shared secret that can be leaked or brute-forced. It addresses the symptom, not the root cause.

**mTLS eliminates the unauthorized client threat at the correct layer.** Phase C moved client authentication into the TLS handshake itself, using cryptographic identity (certificates) rather than shared secrets. An attacker without a CA-signed client certificate cannot complete the handshake — the application is never reached and nothing is logged.

The progression from Phase A to Phase C mirrors the security maturity model recommended by IEC 62443 and NIST SP 800-207 for industrial and zero-trust environments. Each layer addressed the specific gap left by the previous one. mTLS is the industry-standard recommendation for machine-to-machine authentication precisely because it provides cryptographic client identity at the transport layer, with no secret that can be leaked and no application-layer surface for the attacker to reach.

> **WSS encrypts the wire. mTLS decides who gets on it.**

---

## References

- RFC 6455 — The WebSocket Protocol. IETF, 2011.
- RFC 8446 — The Transport Layer Security (TLS) Protocol Version 1.3. IETF, 2018.
- NIST SP 800-207 — Zero Trust Architecture. NIST, 2020.
- IEC 62443-3-3 — Industrial Automation and Control Systems Security: System Security Requirements and Security Levels.
- MITRE ATT&CK for ICS — T0830 Adversary-in-the-Middle, T0885 Commonly Used Port.
- OWASP API Security Top 10 — API2: Broken Authentication. OWASP Foundation.
