# Gitea Container

## Deployment Architecture

Gitea is deployed as one of **two containers** inside the `ca-gitea` Container App.
All external traffic passes through the WAF sidecar before reaching Gitea:

```
Internet (HTTPS) → Container Apps Ingress → WAF sidecar :8080 → Gitea :3000
```

The WAF container (`owasp/modsecurity-crs:nginx-alpine`) runs ModSecurity with the
OWASP Core Rule Set in blocking mode. Requests matching CRS rules (SQLi, XSS,
path traversal, Log4Shell, scanner UAs) are rejected with 403 before Gitea sees them.

## Image

`gitea/gitea:latest-rootless`

- Runs as UID 1000 (non-root)
- No extra capabilities required
- Based on Alpine Linux (minimal attack surface)
- Scanned by Trivy in the CI pipeline; accepted CVEs documented in `/.trivyignore`
- Listens on port 3000 (internal only — not exposed via ingress)

## Storage Layout

| Path | Volume | Type | Persistent |
|---|---|---|---|
| `/var/lib/gitea` | `gitea-data` | Azure Files (SMB) | Yes — avatars, attachments, logs |
| `/gitea-repos` | `gitea-repos` | EmptyDir (local) | No — git repositories |
| `/gitea-db` | `gitea-db` | EmptyDir (local) | No — SQLite database |
| `/tmp/gitea-home` | (tmpfs) | Container local | No — git config scratch space |

> **Why EmptyDir for repos?** Azure Files uses SMB, which does not support `chmod`.
> Git's lock-file mechanism calls `chmod` unconditionally when writing repository
> config files during `git init`, returning `EPERM` on SMB. EmptyDir is local to
> the container instance where POSIX permissions work correctly.
>
> **Why EmptyDir for the DB?** SMB does not implement POSIX `fcntl()` advisory
> locks that SQLite requires, causing `database is locked` on every startup.
>
> **Impact:** Git repositories and user accounts are lost on container restart.
> For production: use Azure NFS Files (Premium) or Azure NetApp Files for repos,
> and Azure Database for PostgreSQL for the database.

## Admin Setup (first deploy)

`INSTALL_LOCK=true` is set, so the web installer does not appear. The container starts
directly into production mode. Create the admin user once via the Container Apps exec shell.

> **Important:** The Container App now has two containers (`waf` and `gitea`). You must
> specify `--container gitea` to open a shell inside Gitea, not the WAF container.

```bash
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --container gitea \
  --command /bin/sh
```

Inside the shell — type as a single line:
```sh
gitea admin user create --config /etc/gitea/app.ini --admin --username gitea-admin --password 'your-password' --email your@email.com --must-change-password=false
```

> The config file at `/etc/gitea/app.ini` is generated at container startup by
> `environment-to-ini` from the environment variables. It is not persisted to Azure Files.

After a container restart the admin user must be recreated using the same command.

## Environment Variables (key security settings)

| Variable | Value | Purpose |
|---|---|---|
| `GITEA__security__INSTALL_LOCK` | `true` | Skip web installer, start in production mode |
| `GITEA__service__DISABLE_REGISTRATION` | `true` | No self-signup |
| `GITEA__service__REQUIRE_SIGNIN_VIEW` | `true` | No anonymous browsing |
| `GITEA__server__DISABLE_SSH` | `true` | HTTPS-only git operations |
| `GITEA__server__START_SSH_SERVER` | `false` | No SSH server started |
| `GITEA__database__DB_TYPE` | `sqlite3` | Database engine |
| `GITEA__database__PATH` | `/gitea-db/gitea.db` | DB on EmptyDir (local, POSIX-lockable) |
| `GITEA__git__HOME_PATH` | `/tmp/gitea-home` | Git config scratch dir (Azure Files SMB chmod fix) |
| `GITEA__security__SECRET_KEY` | (from Key Vault) | Session signing key — prevents token forgery |
| `GITEA__session__COOKIE_SECURE` | `true` | Session cookie only sent over HTTPS, never plain HTTP |
| `GITEA__session__SAME_SITE` | `lax` | Prevents CSRF — cookie not sent on cross-origin POST requests |
| `GITEA__session__SESSION_LIFE_TIME` | `3600` | Session expires after 1 hour — limits stolen-cookie replay window |
| `GITEA__security__REVERSE_PROXY_LIMIT` | `1` | Trust one proxy hop (the WAF sidecar on localhost) |
| `GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES` | `127.0.0.1/8` | WAF is on localhost — real client IP read from X-Forwarded-For |
| `GITEA__log__LEVEL` | `Info` | Log verbosity |
| `GITEA__log__ROOT_PATH` | `/var/lib/gitea/log` | Log files on Azure Files |

## WAF Sidecar Environment Variables

| Variable | Value | Purpose |
|---|---|---|
| `BACKEND` | `http://localhost:3000` | Proxy target (Gitea internal port) |
| `MODSEC_RULE_ENGINE` | `On` | Blocking mode (DetectionOnly = log only) |
| `PARANOIA` | `1` | OWASP CRS paranoia level (1=default, low false-positives) |
| `ANOMALY_INBOUND` | `5` | Inbound anomaly score threshold (CRS default) |
| `PORT` | `8080` | WAF listening port (non-root compatible) |
| `MODSEC_REQ_BODY_LIMIT` | `52428800` | 50 MiB body limit for git push payloads |

## Security Hardening Summary

| Setting / Component | Value | Why |
|---|---|---|
| `DISABLE_REGISTRATION` | `true` | No self-signup; admin creates all accounts |
| `REQUIRE_SIGNIN_VIEW` | `true` | No anonymous repository browsing |
| `DISABLE_SSH` | `true` | Reduces attack surface; HTTPS-only |
| `INSTALL_LOCK` | `true` | Prevents unauthenticated initial configuration |
| `COOKIE_SECURE` | `true` | Session cookie rejected by browser over plain HTTP |
| `SAME_SITE` | `lax` | Prevents CSRF via cross-origin cookie submission |
| `SESSION_LIFE_TIME` | `3600` (1 h) | Stolen cookie expires quickly; forces re-authentication |
| `REVERSE_PROXY_LIMIT` | `1` | Real client IPs logged correctly; rate limiting works |
| Image | `latest-rootless` (UID 1000) | No root in container |
| Secrets | Key Vault references | No plaintext passwords in config or env |
| Replicas | max 1 | SQLite requires single writer |
| WAF sidecar | ModSecurity + OWASP CRS (blocking) | Blocks SQLi, XSS, path traversal — the primary XSS defence that protects cookies |

## Entra ID OIDC Setup (optional)

If an Entra ID app registration is available:

1. Admin Panel → Authentication Sources → Add OAuth2 Source
2. Provider: `OpenID Connect`
3. Name: `EntraID`
4. Discovery URL: `https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration`
5. Client ID: from app registration
6. Client Secret: from Key Vault secret `gitea-oidc-client-secret`

> Student subscriptions may have app registration creation restricted by the tenant admin.
> The deployment works without OIDC — set `GITEA_OIDC_CLIENT_SECRET=not-configured` in
> GitHub secrets and the Key Vault will store that placeholder value.
