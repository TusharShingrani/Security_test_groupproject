# Gitea Container

## Image

`gitea/gitea:latest-rootless`

- Runs as UID 1000 (non-root)
- No extra capabilities required
- Based on Alpine Linux (minimal attack surface)
- Scanned by Trivy in the CI pipeline; accepted CVEs documented in `/.trivyignore`

## Storage Layout

| Path | Volume | Type | Persistent |
|---|---|---|---|
| `/var/lib/gitea` | `gitea-data` | Azure Files (SMB) | Yes — repos, avatars, attachments, logs |
| `/gitea-db` | `gitea-db` | EmptyDir (local) | No — SQLite database only |
| `/tmp/gitea-home` | (tmpfs) | Container local | No — git config scratch space |

> **Why EmptyDir for the DB?** Azure Files uses SMB, which does not implement the POSIX
> `fcntl()` advisory locks that SQLite requires. Placing the DB on Azure Files causes
> `migrate: sync: database is locked` on every startup. The EmptyDir volume is local to
> the container instance where POSIX locking works correctly.
>
> **Impact:** User accounts and Gitea settings are lost when the container restarts.
> Git repository data on Azure Files is unaffected. For production, replace SQLite with
> Azure Database for PostgreSQL Flexible Server.

## Admin Setup (first deploy)

`INSTALL_LOCK=true` is set, so the web installer does not appear. The container starts
directly into production mode. Create the admin user once via the Container Apps exec shell:

```bash
# Open a shell in the running container
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
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
| `GITEA__security__SECRET_KEY` | (from Key Vault) | Session signing key |
| `GITEA__log__LEVEL` | `Info` | Log verbosity |
| `GITEA__log__ROOT_PATH` | `/var/lib/gitea/log` | Log files on Azure Files |

## Security Hardening Summary

| Setting | Value | Why |
|---|---|---|
| `DISABLE_REGISTRATION` | `true` | No self-signup; admin creates all accounts |
| `REQUIRE_SIGNIN_VIEW` | `true` | No anonymous repository browsing |
| `DISABLE_SSH` | `true` | Reduces attack surface; HTTPS-only |
| `INSTALL_LOCK` | `true` | Prevents unauthenticated initial configuration |
| Image | `latest-rootless` (UID 1000) | No root in container |
| Secrets | Key Vault references | No plaintext passwords in config or env |
| Replicas | max 1 | SQLite requires single writer |

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
