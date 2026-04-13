# Risk Matrix

Probability: 1 (Rare) → 5 (Almost Certain)  
Impact: 1 (Negligible) → 5 (Critical)  
Risk Score = Probability × Impact

| # | Risk | Probability | Impact | Score | Mitigation | Residual Risk |
|---|---|---|---|---|---|---|
| R1 | Unauthorized access via self-registration | 4 | 4 | 16 | `DISABLE_REGISTRATION=true` | Low (1×2=2) |
| R2 | Brute force admin login | 3 | 5 | 15 | Gitea rate limiting + TOTP MFA + failed-login alert | Low (1×2=2) |
| R3 | Secret leaked in commit | 3 | 5 | 15 | Gitleaks pipeline gate | Low (1×3=3) |
| R4 | Privilege escalation to admin | 2 | 5 | 10 | Gitea RBAC (`--admin` flag required) | Low (1×2=2) |
| R5 | Container escape via root | 2 | 5 | 10 | Rootless image UID 1000, no extra capabilities | Low (1×3=3) |
| R6 | Secret exposed in environment | 3 | 4 | 12 | Key Vault + Managed Identity (no plaintext secrets) | Low (1×2=2) |
| R7 | Insecure IaC deployed | 3 | 4 | 12 | Checkov pipeline gate | Low (1×2=2) |
| R8 | CVE exploitation in container | 3 | 3 | 9 | Trivy scan + `.trivyignore` with documented exceptions | Medium (2×3=6) |
| R9 | Denial of service (traffic spike) | 2 | 3 | 6 | Alert rule + Container Apps scaling | Low (1×2=2) |
| R10 | Log Analytics unavailable | 1 | 3 | 3 | Azure SLA 99.9% + 30-day log retention | Low (1×2=2) |
| R11 | Azure Files data loss | 1 | 5 | 5 | LRS replication (3 copies in region) | Low (1×3=3) |
| R12 | OIDC misconfiguration | 2 | 4 | 8 | Manual setup documented + test validation | Medium (2×2=4) |
| R13 | Web app vulnerability (XSS, SQLi) | 2 | 4 | 8 | ModSecurity WAF sidecar (always on, blocking) + OWASP ZAP DAST (weekly) | Low (1×2=2) |
| R14 | Session cookie hijacking | 2 | 4 | 8 | `COOKIE_SECURE=true` + `SAME_SITE=lax` + 1-hour timeout + HTTPS enforced + WAF blocks XSS | Low (1×2=2) |

## Risk Heat Map

```
Impact
  5 │  R2  R3  │ R4  R5  │ R1         │
    │           │         │           │
  4 │           │ R6  R7  │ R12 R13   │
    │           │         │           │
  3 │           │ R8  R9  │           │
    │           │         │           │
  2 │           │         │           │
    │           │         │           │
  1 │           │         │ R10        │
    └───────────┴─────────┴───────────►
         1-2         3         4-5    Probability

  High (12-25)  Medium (6-11)  Low (1-5)
```

## Controls Summary

| Control | Risks Addressed |
|---|---|
| `DISABLE_REGISTRATION=true` | R1 |
| `REQUIRE_SIGNIN_VIEW=true` | R1 |
| Gitea TOTP MFA | R2 |
| Gitea rate limiting + `alert-failed-logins` | R2 |
| Gitleaks pipeline gate | R3 |
| Gitea RBAC (`--admin` flag) | R4 |
| Rootless container (UID 1000) | R5 |
| Key Vault + Managed Identity | R6 |
| Checkov pipeline gate | R7 |
| Trivy pipeline gate + `.trivyignore` | R8 |
| `alert-abnormal-traffic` + Container Apps scaling | R9 |
| Log Analytics 30-day retention | R10 |
| Azure Files LRS replication | R11 |
| OIDC federated credentials (documented setup) | R12 |
| ModSecurity WAF sidecar (always-on, blocking mode) | R13, R14 |
| OWASP ZAP DAST baseline (weekly schedule) | R13 |
| `COOKIE_SECURE=true` + `SAME_SITE=lax` + 1-hour timeout | R14 |
| HTTPS enforced via Container Apps ingress | R14 |

## Notes on Accepted Residual Risks

**R8 — CVE in container image (Medium residual):**  
13 Go stdlib CVEs are accepted in `.trivyignore` because they require a rebuild
of the Gitea binary by the upstream maintainers, not a configuration change.
These are monitored; if Gitea releases an updated image the ignore entries will
be reviewed. Rootless container (R5 mitigation) limits exploitation impact.

**R12 — OIDC misconfiguration (Medium residual):**  
Entra ID OIDC is not configured in the current PoC deployment (student
subscription restricts app registration creation via the portal). The Azure CLI
workaround is documented in `docs/architecture/resource-assessment.md`. Gitea
TOTP MFA (R2 mitigation) serves as a compensating control.
