# WSS Unauthorized Client Attack — Diagram

## Infrastructure

```
Azure VNet 10.0.0.0/16
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  ┌──────────────────┐          ┌──────────────────────────┐    │
│  │   digital-twin   │          │      software-agent      │    │
│  │   10.0.1.10      │──WSS──▶  │      10.0.1.20:8443      │    │
│  │   (twin.py)      │          │      (agent.py)          │    │
│  └──────────────────┘          └──────────────────────────┘    │
│           ▲                               ▲                     │
│    public IP                              │                     │
│  (SSH entry point)                        │                     │
│                                           │                     │
│  ┌──────────────────┐                     │                     │
│  │    attacker      │──WSS──────────────▶ │                     │
│  │   10.0.1.30      │   (same protocol,   │                     │
│  │  (attacker.py)   │    no token)        │                     │
│  └──────────────────┘                     │                     │
│                                           │                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase A — The Vulnerability (AUTH_MODE=none)

```mermaid
sequenceDiagram
    participant T as digital-twin<br/>(10.0.1.10)
    participant A as software-agent<br/>(10.0.1.20:8443)
    participant X as attacker<br/>(10.0.1.30)

    note over T,A: Normal operation — twin sends every 10s
    T->>+A: WSS connect (TLS handshake ✓)
    T->>A: {"source":"digital-twin", "electrolyzer_enable": true}
    A-->>T: {"status": "accepted"}
    note over A: PLC state → RUNNING ✅

    note over X,A: Attack — attacker speaks the same protocol
    X->>+A: WSS connect (TLS handshake ✓)
    note over A: TLS only proves server identity.<br/>Client identity = unverified.
    X->>A: {"source":"attacker", "electrolyzer_enable": false}
    A-->>X: {"status": "accepted"}
    note over A: PLC state → STOPPED ⚠️

    note over T,X: WSS encrypted the wire — but did NOT authenticate the sender
```

---

## Phase B — The Fix (AUTH_MODE=token)

```mermaid
sequenceDiagram
    participant T as digital-twin<br/>(10.0.1.10)
    participant A as software-agent<br/>(10.0.1.20:8443)
    participant X as attacker<br/>(10.0.1.30)

    note over T,A: Twin knows the shared token
    T->>+A: WSS connect (TLS handshake ✓)
    T->>A: {"source":"digital-twin", "electrolyzer_enable": true,<br/>"token": "changeme"}
    A-->>T: {"status": "accepted"}
    note over A: Token matches → PLC state → RUNNING ✅

    note over X,A: Attacker does NOT know the token
    X->>+A: WSS connect (TLS handshake ✓)
    X->>A: {"source":"attacker", "electrolyzer_enable": false}
    note over A: No token in message → REJECT
    A-->>X: {"status": "unauthorized"}
    note over A: PLC state unchanged ✅

    note over T,X: Application-layer auth stops the attack.<br/>Transport encryption alone is not enough.
```

---

## Key Takeaway

| Property | WSS (TLS transport) | Token auth (Phase B) |
|---|---|---|
| Wire encryption | Yes | Yes |
| Server identity verified | Yes (server cert) | Yes (server cert) |
| **Client identity verified** | **No** | **Yes** |
| Attacker blocked | No | Yes |

> **WSS encrypts the conversation. It does not verify who is speaking.**
> Authentication must be enforced at the application layer.
