# Architecture Overview

## High-Level Diagram

```
             Internet
                │
                ▼ HTTPS (TLS 1.2+)
    ┌───────────────────────────┐
    │  Azure Container Apps     │
    │  Ingress (managed)        │
    └────────────┬──────────────┘
                 │ port 8080
                 ▼
    ┌────────────────────────────────────────┐
    │            ca-gitea (Container App)    │
    │                                        │
    │  ┌──────────────────────────────────┐  │
    │  │  WAF sidecar                     │  │
    │  │  owasp/modsecurity-crs:nginx-alpine│ │
    │  │  Port 8080 — OWASP CRS blocking  │  │
    │  └──────────────┬───────────────────┘  │
    │                 │ localhost:3000        │
    │                 ▼                      │
    │  ┌──────────────────────────────────┐  │
    │  │  Gitea                           │  │
    │  │  gitea/gitea:latest-rootless     │  │
    │  │  UID 1000, Port 3000 (internal)  │  │
    │  └──────┬──────────────┬────────────┘  │
    └─────────┼──────────────┼───────────────┘
              │              │
              ▼              ▼
  ┌──────────────┐  ┌──────────────────┐
  │  Key Vault   │  │  Azure Files     │
  │  kv-gitea-xx │  │  /var/lib/gitea  │
  │  - admin pw  │  │  repos, avatars  │
  │  - secret key│  │  attachments     │
  │  - OIDC sec  │  │  logs            │
  └──────────────┘  └──────────────────┘
        ▲           ┌──────────────────┐
        │ managed   │  EmptyDir (local)│
        │ identity  │  /gitea-db       │
  ┌─────┴──────┐    │  SQLite DB       │
  │  Managed   │    │  (ephemeral)     │
  │  Identity  │    └──────────────────┘
  └────────────┘

  ┌──────────────────┐     ┌──────────────────┐
  │  Log Analytics   │     │  Monitor Alerts  │
  │  law-gitea-sec   │     │  4 alert rules   │
  └──────────────────┘     └──────────────────┘

  Local tooling:
  ┌──────────────────────────────────────────┐
  │  scripts/dast/ OWASP ZAP baseline scan  │  Docker, weekly via dast.yml
  │  scripts/waf/  docker-compose for local │  Manual attack-pattern testing
  └──────────────────────────────────────────┘
```

## Storage Layout

| Path in Container | Volume | Type | Persistent |
|---|---|---|---|
| `/var/lib/gitea` | `gitea-data` | Azure Files (SMB) | Yes — avatars, attachments, logs |
| `/gitea-repos` | `gitea-repos` | EmptyDir (local) | No — git repositories |
| `/gitea-db` | `gitea-db` | EmptyDir (local) | No — SQLite database |
| `/tmp/gitea-home` | (tmpfs) | Container local | No — git config scratch space |

> **Why EmptyDir for repos and DB?** Azure Files uses SMB, which does not support
> `chmod`. Git's lock-file mechanism calls `chmod` unconditionally when writing
> repository config files (e.g. during `git init`), returning `EPERM` on SMB.
> SQLite also requires POSIX `fcntl()` locks unavailable on SMB. Both are moved
> to EmptyDir where POSIX semantics work correctly. Trade-off: repositories and
> user accounts are lost on container restart.
> For production: use Azure NFS Files (Premium tier) or Azure NetApp Files for
> repos (full POSIX support), and Azure Database for PostgreSQL for the DB.

## Trust Boundaries

```
[ Internet ]
      │ HTTPS (TLS 1.2+)
      ▼
[ Container Apps Ingress ]  ← Azure-managed, public endpoint
      │
      ▼
[ Gitea container ]         ← UID 1000, no root
      │               │
      ▼               ▼
[ Key Vault ]    [ Azure Files ]
  access policy    shared key
  (managed id)     (storage-key secret)
```

No direct database or admin port is exposed to the internet. The only inbound
path is HTTPS port 443 through the Container Apps managed ingress.

## CI/CD Trust Boundary

```
[ GitHub Actions ]
      │ OIDC token (no stored secret)
      ▼
[ Azure AD / Entra ID ]
      │ validates federated credential
      ▼
[ Azure — Contributor role on rg-gitea-sec ]
      │
      ▼
[ Terraform apply ]
```

The deploy job authenticates via OIDC federated credentials on the
`wss-poc-github-oidc` app registration. No client secret is stored in GitHub.

## Security Controls per Layer

| Layer | Control | Implementation |
|---|---|---|
| Network | HTTPS-only ingress | Container Apps managed TLS, no SSH exposed |
| Application | No self-signup | `DISABLE_REGISTRATION=true` |
| Application | Auth required | `REQUIRE_SIGNIN_VIEW=true` |
| Application | No installer | `INSTALL_LOCK=true` |
| Application | MFA | Gitea TOTP (`docs/evidence/mfa-setup.md`) |
| Application | Session cookie HTTPS-only | `COOKIE_SECURE=true` — cookie never sent over plain HTTP |
| Application | CSRF protection | `SAME_SITE=lax` — cookie not submitted on cross-origin POST |
| Application | Session timeout | `SESSION_LIFE_TIME=3600` — 1-hour session cap |
| Application | Real IP tracking | `REVERSE_PROXY_LIMIT=1` — WAF forwards real client IP |
| Identity | Admin RBAC | Gitea role-based access control |
| Secrets | No plaintext creds | Key Vault + Managed Identity |
| Container | Non-root | `latest-rootless` image (UID 1000) |
| Container | Minimal surface | Alpine base, SSH disabled |
| IaC | Config validation | Checkov scan + terraform validate in pipeline |
| Code | Secret detection | Gitleaks on every push |
| Image | CVE scanning | Trivy — fails on unaccepted CRITICAL/HIGH |
| DAST | Web app testing | OWASP ZAP baseline (`scripts/dast/`, `dast.yml`) |
| WAF | Attack blocking | NGINX + ModSecurity + OWASP CRS (sidecar in `terraform/aca.tf`, always on) |
| Monitoring | Alerting | Log Analytics + 4 Azure Monitor alert rules |
| CI/CD | No stored secrets | OIDC federated credentials |

## Deployed Resources

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-gitea-sec` | All project resources |
| Container Apps Environment | `cae-gitea-sec` | Managed container runtime |
| Container App | `ca-gitea` | Gitea application |
| Log Analytics Workspace | `law-gitea-sec` | Container logs + alerting |
| Monitor Action Group | `ag-gitea-sec` | Alert notification target |
| Monitor Alert Rules | 4 rules (ARM deployment) | Security event detection |
| User Assigned Identity | `id-gitea-sec` | Managed identity for Key Vault |
| Key Vault | `kv-gitea-vcqg9x` | Secrets (admin password, secret key, OIDC) |
| Storage Account | `sagiteavcqg9x` | Azure Files for persistent storage |
| File Share | `gitea-data` (10 GiB) | Mounted at `/var/lib/gitea` |

Live URL: `https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io`
