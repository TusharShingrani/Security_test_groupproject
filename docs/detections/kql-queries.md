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

## 6. Local Password Auth Attempts

Detects direct password-based logins. With `DISABLE_REGISTRATION=true` only
the admin account can log in locally — any volume here warrants investigation.
(When Entra ID OIDC is enabled this query can distinguish OIDC from local logins.)

```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-gitea"
| where Log_s contains "user signin" or Log_s contains "Logged in as"
      or (Log_s contains "Failed" and Log_s contains "login")
| extend AuthResult = case(
    Log_s contains "Failed" or Log_s contains "Invalid", "FAILED",
    Log_s contains "Logged in" or Log_s contains "signed in", "SUCCESS",
    "UNKNOWN"
  )
| extend Username = extract(@'user[=:\s"]+([^\s",]+)', 1, Log_s)
| project TimeGenerated, AuthResult, Username, Log_s
| order by TimeGenerated desc
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

---

## How to Trigger Each Alert (for evidence capture)

### alert-failed-logins (MC-02)

Run `scripts/validation/brute-force-sim.py` — it sends ≥7 POST /user/login
requests with an intentionally wrong password within a 1-minute window:

```bash
cd scripts/validation
python3 brute-force-sim.py
# Wait ~5 min, then check Azure Monitor → Alerts
```

Expected: alert fires with `Fired` state in Azure Monitor.
Run KQL query **#1** to confirm log entries.

### alert-container-restarts

Trigger a container restart via:

```bash
az containerapp revision restart \
  --name ca-gitea \
  --resource-group rg-gitea-sec \
  --revision "$(az containerapp revision list \
      --name ca-gitea \
      --resource-group rg-gitea-sec \
      --query '[0].name' -o tsv)"
```

Expected: `ContainerAppSystemLogs_CL` receives `Restarting` entries. Run KQL query **#2**.

### alert-abnormal-traffic

Run `scripts/validation/traffic-gen.sh` to send >500 requests in one minute:

```bash
cd scripts/validation
./traffic-gen.sh
# Wait ~2 min, then check Azure Monitor → Alerts
```

Expected: alert fires. Run KQL query **#5** to visualise the spike.

### alert-local-auth-attempt

This alert fires on any sign-in that does not go through OAuth2/OIDC. Because
OIDC is not configured in the current PoC deployment, any successful or failed
admin login via the Gitea web UI counts. Run the brute-force sim or simply
attempt to log in manually via the browser.

Run KQL query **#6** to see local auth events in the log stream.
