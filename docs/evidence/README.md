# Evidence Placeholders

After running the security validation tests, capture screenshots/logs here.

## Structure

```
docs/evidence/
├── phase1-unauthorized-access/
│   ├── screenshot-registration-blocked.png
│   └── screenshot-require-signin.png
├── phase2-brute-force/
│   ├── screenshot-rate-limit.png
│   └── screenshot-alert-fired.png
├── phase3-privilege-escalation/
│   ├── screenshot-admin-403.png
│   └── log-access-denied.txt
├── phase4-secret-leakage/
│   ├── screenshot-gitleaks-fail.png
│   └── pipeline-run-url.txt
├── phase5-insecure-terraform/
│   ├── screenshot-checkov-fail.png
│   └── checkov-output.txt
├── phase6-container-vulnerabilities/
│   ├── trivy-scan-output.txt
│   └── screenshot-pipeline-block.png
└── phase7-monitoring/
    ├── screenshot-log-analytics-query.png
    ├── screenshot-alert-fired.png
    └── kql-results.txt
```

## Validation Checklist

- [ ] MC-01: Unauthenticated access blocked (REQUIRE_SIGNIN_VIEW)
- [ ] MC-01: Registration blocked (DISABLE_REGISTRATION)
- [ ] MC-02: Brute force alert fired in Log Analytics
- [ ] MC-03: Non-admin /admin access returns 403
- [ ] MC-04: Gitleaks pipeline blocked fake secret commit
- [ ] MC-05: Checkov blocked insecure Terraform config
- [ ] MC-06: Trivy scan output captured
- [ ] KQL query results captured for all 8 queries
- [ ] 4 alert rules confirmed active in Azure Portal
