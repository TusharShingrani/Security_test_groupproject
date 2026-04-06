# Threat Model

## System Overview

Gitea is a self-hosted Git service running as a container on Azure Container Apps, protected by Zero Trust controls, Key Vault secrets management, and DevSecOps automation.

## Assets

| Asset | Value | Location |
|---|---|---|
| Source code repositories | High | Azure Files (gitea-data share) |
| User credentials | High | Entra ID / Key Vault |
| Gitea admin password | Critical | Azure Key Vault |
| OIDC client secret | Critical | Azure Key Vault |
| SQLite database | High | Azure Files |
| Container image | Medium | Docker Hub (gitea/gitea:1.21-rootless) |

## Trust Zones

```
Zone 1 (Internet)         — Untrusted
Zone 2 (Container Apps)   — Semi-trusted (TLS terminated, auth required)
Zone 3 (Azure Backend)    — Trusted (Key Vault, Storage, Log Analytics)
Zone 4 (Entra ID)         — Trusted identity provider
```

## STRIDE Threat Analysis

### Spoofing

| Threat | Control |
|---|---|
| Attacker spoofs legitimate user login | Entra ID MFA + OIDC — local login disabled |
| Attacker spoofs admin account | Admin account protected by Key Vault password + MFA |
| Forged JWT token | Entra ID signs tokens — cannot be forged without private key |

### Tampering

| Threat | Control |
|---|---|
| Modify source code repositories | Gitea access control (RBAC) + Entra ID auth |
| Modify container at runtime | Read-only container filesystem (where possible) |
| Tamper with secrets | Key Vault RBAC — only managed identity can read |
| Modify Terraform state | Storage account key required — managed by Terraform backend |

### Repudiation

| Threat | Control |
|---|---|
| User denies making changes | Log Analytics captures all Gitea activity |
| Admin denies config change | Container logs forwarded to Log Analytics |

### Information Disclosure

| Threat | Control |
|---|---|
| Secret leakage in code | Gitleaks scan — fails pipeline if secrets detected |
| Secret leakage in config | Key Vault — secrets never in plaintext config |
| Sensitive data in logs | Gitea log level set to Info (no password logging) |
| Unauthenticated repo access | `REQUIRE_SIGNIN_VIEW=true` — all content requires login |

### Denial of Service

| Threat | Control |
|---|---|
| Brute force login | Gitea built-in rate limiting + Entra ID lockout |
| Container crash loop | Alert rule for restarts + auto-restart by Container Apps |
| Storage exhaustion | File share quota (10GB limit) |
| Abnormal traffic spike | Alert rule triggers on >500 req/min |

### Elevation of Privilege

| Threat | Control |
|---|---|
| Container escape to host | Rootless image (UID 1000) — no root inside container |
| Gaining admin via registration | `DISABLE_REGISTRATION=true` |
| Accessing Key Vault directly | Only managed identity has secret read permission |
| Accessing another tenant's resources | OIDC scoped to specific tenant ID |
