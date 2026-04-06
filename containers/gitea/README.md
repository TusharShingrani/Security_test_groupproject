# Gitea Container

## Image

`gitea/gitea:1.21-rootless`

- Runs as UID 1000 (non-root)
- No capabilities required
- Data path: `/var/lib/gitea` (mounted from Azure Files)

## Post-Deployment Admin Setup

After the first `terraform apply`, Gitea will be running but no admin user exists yet.
Complete setup via the Gitea web installer or CLI:

### Option A — Web installer (first visit)

1. Navigate to the Gitea URL
2. The installer will appear (INSTALL_LOCK is false initially)
3. Database: SQLite3, path `/var/lib/gitea/data/gitea.db`
4. Create admin account in the installer form
5. After install, go to Admin Panel → Configuration → disable registration

### Option B — CLI via Container Apps exec

```bash
az containerapp exec \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --command "gitea admin user create --admin --username gitea-admin --email admin@example.com --password <password>"
```

## Entra ID OIDC Setup (after admin login)

1. Admin Panel → Authentication Sources → Add OAuth2 Source
2. Provider: `OpenID Connect`
3. Name: `EntraID`
4. Discovery URL: `https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration`
5. Client ID: from app registration
6. Client Secret: from Key Vault secret `gitea-oidc-client-secret`
7. Required claim (restrict to your tenant): set Tenant ID in additional scopes

## Security Hardening Applied

| Setting | Value | Why |
|---|---|---|
| `DISABLE_REGISTRATION` | `true` | No self-signup |
| `REQUIRE_SIGNIN_VIEW` | `true` | No anonymous browsing |
| `DISABLE_SSH` | `true` | HTTPS-only git operations |
| `START_SSH_SERVER` | `false` | No SSH exposure |
| Image | rootless (UID 1000) | No root in container |
| Secrets | Key Vault references | No plaintext secrets |
