# Threat Model

## System Overview

Gitea is a self-hosted Git service running as a container on Azure Container Apps.
All external traffic passes through a ModSecurity WAF sidecar before reaching Gitea.
Authentication uses local Gitea accounts (no Entra ID OIDC — student subscription
restriction) hardened with TOTP MFA, session controls, and Zero Trust access policies.

---

## Assets

| Asset | Value | Location |
|---|---|---|
| Source code repositories | High | Azure Files (gitea-data share, SMB) |
| Gitea admin password | Critical | Azure Key Vault (`gitea-admin-password`) |
| Gitea session secret key | Critical | Azure Key Vault (`gitea-secret-key`) |
| OIDC client secret (placeholder) | Low | Azure Key Vault (value: `not-configured`) |
| Session cookies (runtime) | High | Browser — protected by HTTPS + COOKIE_SECURE + SAME_SITE |
| SQLite database (user accounts) | Medium | EmptyDir volume (ephemeral — lost on restart) |
| Container image | Medium | Docker Hub (`gitea/gitea:latest-rootless`) |
| Terraform state | High | Azure Blob (`tfstatepoc2` storage account) |

---

## Trust Zones

```
Zone 1 (Internet)           — Untrusted
Zone 2 (WAF sidecar)        — Semi-trusted (ModSecurity + OWASP CRS, blocking mode)
Zone 3 (Gitea container)    — Semi-trusted (authenticated only; runs as UID 1000)
Zone 4 (Azure Backend)      — Trusted (Key Vault, Storage Account, Log Analytics)
Zone 5 (GitHub Actions)     — Trusted CI/CD (OIDC federated — no stored secret)
```

> **Note:** Entra ID is NOT used as an identity provider in this deployment.
> Authentication is handled entirely by Gitea's local account system with TOTP MFA
> as the second factor. The student subscription restricts app registration creation
> via the portal; adding Entra ID OIDC would require Azure CLI with tenant admin help.

---

## STRIDE Threat Analysis

### Spoofing

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| Attacker guesses admin password | Medium | Strong password in Key Vault + TOTP MFA (second factor required) | Low |
| Attacker replays a stolen session cookie | Medium | `COOKIE_SECURE=true` (HTTPS only) + `SAME_SITE=lax` (no cross-origin) + 1-hour expiry | Low |
| Attacker forges a session token | Low | `SECRET_KEY` stored in Key Vault — cannot sign tokens without it | Low |
| Attacker self-registers a new account | High (if unmitigated) | `DISABLE_REGISTRATION=true` — registration returns 403 | Low |
| Attacker uses Gitea web installer to set up a new admin | High (if unmitigated) | `INSTALL_LOCK=true` — installer page inaccessible | Low |

---

### Tampering

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| Modify source code repositories without permission | Medium | Gitea RBAC — only admin account has write access | Low |
| Modify container at runtime | Low | Rootless image (UID 1000), no privilege escalation path | Low |
| Tamper with secrets in Key Vault | Low | Access policy scoped to managed identity only — no other principal has access | Low |
| Modify Terraform state | Low | Storage account shared key required — held by Terraform backend only | Low |
| Inject malicious HTTP payload (SQLi, XSS) | High (if unmitigated) | WAF sidecar (ModSecurity + OWASP CRS) blocks injection patterns before Gitea processes them | Low |
| Deploy insecure infrastructure change | Medium | Checkov pipeline gate blocks non-compliant Terraform before apply | Low |

---

### Repudiation

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| User denies making a repository change | Low | Log Analytics captures all Gitea HTTP activity with real client IPs (reverse proxy trust configured) | Low |
| Admin denies configuration change | Low | Container startup logs and environment forwarded to Log Analytics | Low |
| Attacker denies an attack attempt | Medium | WAF audit log entries written to stdout → Container Apps console logs → Log Analytics (KQL query #9) | Low |
| CI/CD pipeline action denied | Low | GitHub Actions audit log + OIDC token claims identify the workflow run | Low |

---

### Information Disclosure

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| Secret committed to git history | Medium | Gitleaks scans every push — pipeline fails if any secret pattern detected | Low |
| Secret in plaintext config or environment | Low | All secrets referenced from Key Vault — no plaintext values in Terraform or env | Low |
| Sensitive data exposed in logs | Low | Gitea log level = Info (no password or token logging) | Low |
| Unauthenticated repository browsing | High (if unmitigated) | `REQUIRE_SIGNIN_VIEW=true` — every page redirects to login | Low |
| Session cookie intercepted in transit | Medium | HTTPS enforced by Container Apps ingress (TLS 1.2+) + `COOKIE_SECURE=true` | Low |
| Session cookie stolen via XSS | Medium | WAF (ModSecurity) blocks XSS payloads before Gitea renders them; `SAME_SITE=lax` limits damage if one slips through | Low |
| CVE exploitation leaking container data | Medium | Trivy scan + rootless container (UID 1000) limits blast radius | Medium |

---

### Denial of Service

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| Brute force login | High (if unmitigated) | Gitea built-in rate limiting + `alert-failed-logins` fires after ≥5 failures in 5 min | Low |
| TOTP bypassed by exhaustive OTP guessing | Low | Gitea invalidates TOTP codes after single use; rate limiting blocks rapid attempts | Low |
| Container crash loop | Low | Azure Container Apps auto-restart + `alert-container-restarts` alert | Low |
| Storage exhaustion (repos) | Low | Azure Files share quota (10 GiB hard limit) | Low |
| Abnormal HTTP traffic spike | Medium | `alert-abnormal-traffic` fires at >500 req/min; WAF can absorb request inspection overhead | Low |
| Malformed request exhausting Gitea | Medium | WAF sidecar drops malformed/oversized requests before they reach Gitea | Low |

---

### Elevation of Privilege

| Threat | Likelihood | Control | Residual |
|---|---|---|---|
| Container escape to host | Low | Rootless image (UID 1000) — no root inside container; no extra Linux capabilities | Low |
| Gaining admin role via self-registration | High (if unmitigated) | `DISABLE_REGISTRATION=true` — no accounts can be created via the web UI | Low |
| Non-admin user accessing `/admin` routes | Medium | Gitea RBAC — admin flag required; tested by `check-access-controls.sh` | Low |
| Accessing Key Vault without managed identity | Low | Access policy allows only `id-gitea-sec` managed identity to read secrets | Low |
| Path traversal to access host filesystem | Medium (if unmitigated) | WAF (OWASP CRS) blocks path traversal patterns (e.g. `/../../../etc/passwd`) | Low |
| Exploiting a CVE to gain elevated privileges | Medium (if unmitigated) | Trivy scan + rootless container limits privilege escalation paths post-exploit | Medium |

---

## Gaps and Accepted Limitations

| Gap | Reason | Compensating Control |
|---|---|---|
| No Entra ID OIDC (no centrally managed identities) | Student subscription restricts app registration portal | Local Gitea accounts + TOTP MFA; single admin account minimises exposure |
| SQLite DB is ephemeral (EmptyDir) | Azure Files SMB does not support POSIX file locks | Only user accounts are lost on restart; git repos on Azure Files are unaffected |
| No Content Security Policy header | WAF NGINX template doesn't expose a header-injection env var without a custom image | WAF blocks XSS payloads before they reach the browser; Gitea sets X-Frame-Options and X-Content-Type-Options by default |
| No IP allowlist on Key Vault | Container Apps Consumption plan has no VNet injection | Access policy limits reads to the managed identity only — network ACLs add defence-in-depth but are not the primary control |
| Trivy CVEs exit-code 0 (non-blocking) | New Go stdlib CVEs are published faster than Gitea rebuilds their image | All accepted CVEs documented in `.trivyignore` with justification; rootless container limits blast radius |
