# Architecture Overview

## High-Level Diagram

```
             Internet
                │
                ▼
    ┌─────────────────────┐
    │  Azure Container    │  HTTPS (TLS 1.2+)
    │  Apps Ingress       │  External IP managed by Azure
    └────────┬────────────┘
             │
             ▼
    ┌─────────────────────┐
    │   Gitea Container   │  gitea/gitea:1.21-rootless
    │   App (ca-gitea)    │  Port 3000 (internal only)
    │                     │
    │  UID: 1000 (non-root│
    └──────┬──────┬───────┘
           │      │
           │      └──────────────────────────────┐
           │                                     │
           ▼                                     ▼
  ┌─────────────────┐                 ┌─────────────────────┐
  │  Azure Key Vault │                │   Azure Files        │
  │  (kv-gitea-xxxx) │                │  (gitea-data share)  │
  │                  │                │                      │
  │  - admin password│                │  /var/lib/gitea      │
  │  - secret key    │                │  (repos + SQLite DB) │
  │  - OIDC secret   │                └─────────────────────┘
  └─────────────────┘
           ▲
           │ (managed identity — no password)
  ┌────────┴──────────┐
  │  User Assigned    │
  │  Managed Identity │
  │  (id-gitea-sec)   │
  └───────────────────┘

  ┌───────────────────┐
  │  Log Analytics    │    All container logs
  │  Workspace        │◀── + 4 alert rules
  │  (law-gitea-sec)  │
  └───────────────────┘

  ┌───────────────────┐
  │  Microsoft        │    OIDC / OAuth2 login
  │  Entra ID         │◀── (replaces local accounts)
  └───────────────────┘
```

## Trust Boundaries

```
[ Internet ] ──── HTTPS ──── [ Container Apps Ingress ] ──── [ Gitea ]
                                                                  │
             ┌────────────────────────────────────────────────────┤
             │                                                    │
    [ Key Vault ]                                      [ Azure Files ]
    (managed identity only)                           (Storage Account)
```

## Security Controls per Layer

| Layer | Control |
|---|---|
| Network | Container Apps managed ingress, HTTPS only, no SSH exposed |
| Identity | Entra ID OIDC, RBAC roles, managed identity (no passwords) |
| Secrets | Key Vault — no secrets in code, env, or config files |
| Container | Rootless image (UID 1000), read-only where possible |
| IaC | Checkov scan, terraform validate, fmt check in CI |
| Code | Gitleaks secret scanning on every push |
| Image | Trivy scan — fails on CRITICAL/HIGH CVEs |
| Monitoring | Log Analytics + 4 alert rules (logins, restarts, traffic) |
