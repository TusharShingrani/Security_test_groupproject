# KQL Detection Queries

Run these in Log Analytics Workspace → Logs.

---

## 1. Failed Login Attempts

Detects repeated failed logins — possible brute force.

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| where Log_s contains "Failed" and Log_s contains "login"
| extend IP = extract(@"from\s+(\S+)", 1, Log_s)
| summarize FailedAttempts = count() by IP, bin(TimeGenerated, 5m)
| where FailedAttempts >= 5
| order by FailedAttempts desc
```

---

## 2. Container Restarts

Detects crash-loops or OOM kills.

```kql
ContainerAppSystemLogs_CL
| where RevisionName_s contains "ca-gitea"
| where Log_s contains "Restarting" or Log_s contains "OOMKilled" or Log_s contains "Error"
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

---

## 3. All Gitea Access Logs

Full request log for audit trail.

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| extend Method = extract(@'"(\w+)\s', 1, Log_s)
| extend Path = extract(@'"\w+\s+(\S+)', 1, Log_s)
| extend StatusCode = extract(@'"\s+(\d{3})\s', 1, Log_s)
| project TimeGenerated, Method, Path, StatusCode, Log_s
| order by TimeGenerated desc
```

---

## 4. Unauthorized Admin Access Attempts

Detects non-admin users attempting to reach /admin paths.

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| where Log_s contains "/admin" and Log_s contains "403"
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

---

## 5. Abnormal Traffic Volume

Detects request spikes — possible DoS or scanning.

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| summarize RequestCount = count() by bin(TimeGenerated, 1m)
| where RequestCount > 200
| render timechart
```

---

## 6. OIDC vs Local Login Comparison

Shows ratio of Entra ID logins vs local logins (local should be 0).

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| where Log_s contains "signin" or Log_s contains "oauth2"
| extend LoginType = iff(Log_s contains "oauth2", "Entra ID OIDC", "Local")
| summarize Count = count() by LoginType, bin(TimeGenerated, 1h)
| render columnchart
```

---

## 7. Key Vault Access Log

Shows all secret reads by the managed identity.

```kql
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName == "SecretGet"
| project TimeGenerated, identity_claim_appid_g, ResultType, requestUri_s
| order by TimeGenerated desc
```

---

## 8. Security Alert Summary (last 24h)

Dashboard view of all triggered alerts.

```kql
AlertsManagementResources
| where type == "microsoft.alertsmanagement/alerts"
| where properties.essentials.startDateTime > ago(24h)
| project AlertName = properties.essentials.alertRule,
          Severity = properties.essentials.severity,
          State = properties.essentials.alertState,
          Fired = properties.essentials.startDateTime
| order by Fired desc
```
