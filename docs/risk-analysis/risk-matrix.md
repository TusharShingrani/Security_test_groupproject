# Risk Matrix

Probability: 1 (Rare) → 5 (Almost Certain)
Impact: 1 (Negligible) → 5 (Critical)
Risk Score = Probability × Impact

| # | Risk | Probability | Impact | Score | Mitigation | Residual Risk |
|---|---|---|---|---|---|---|
| R1 | Unauthorized access via registration | 4 | 4 | 16 | DISABLE_REGISTRATION=true | Low (1×2=2) |
| R2 | Brute force admin login | 3 | 5 | 15 | Entra ID MFA + rate limiting | Low (1×3=3) |
| R3 | Secret leaked in commit | 3 | 5 | 15 | Gitleaks pipeline gate | Low (1×3=3) |
| R4 | Privilege escalation to admin | 2 | 5 | 10 | Gitea RBAC + Entra ID groups | Low (1×2=2) |
| R5 | Container escape | 2 | 5 | 10 | Rootless UID 1000, no capabilities | Low (1×3=3) |
| R6 | Secret exposed in environment | 3 | 4 | 12 | Key Vault + managed identity | Low (1×2=2) |
| R7 | Insecure IaC deployed | 3 | 4 | 12 | Checkov pipeline gate | Low (1×2=2) |
| R8 | CVE in container image | 3 | 3 | 9 | Trivy scan + pinned image tag | Medium (2×3=6) |
| R9 | Denial of service (traffic) | 2 | 3 | 6 | Alert rule + Container Apps scaling | Low (1×2=2) |
| R10 | Log Analytics unavailable | 1 | 3 | 3 | Azure SLA 99.9% + retention 30d | Low (1×2=2) |
| R11 | Azure Files data loss | 1 | 5 | 5 | LRS replication (3 copies) | Low (1×3=3) |
| R12 | OIDC misconfiguration | 2 | 4 | 8 | Manual setup + test validation | Medium (2×2=4) |

## Risk Heat Map

```
Impact
  5 │  R2  R3  │ R4  R5  │ R1         │
    │           │         │           │
  4 │           │ R6  R7  │           │
    │           │         │           │
  3 │           │ R8  R9  │ R12        │
    │           │         │           │
  2 │           │         │           │
    │           │         │           │
  1 │           │         │ R10        │
    └───────────┴─────────┴───────────►
         1-2         3         4-5    Probability

  🟥 High (12-25)  🟧 Medium (6-11)  🟩 Low (1-5)
```

## Controls Summary

| Control | Risks Addressed |
|---|---|
| Entra ID OIDC + MFA | R1, R2, R4 |
| Key Vault + Managed Identity | R3, R6 |
| Rootless container | R5 |
| Gitleaks pipeline | R3 |
| Checkov pipeline | R7 |
| Trivy pipeline | R8 |
| Log Analytics alerts | R2, R9 |
| Azure Files LRS | R11 |
