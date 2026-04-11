resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ── Alerts ──────────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "giteasec"
  tags                = local.tags
}

# Alert 1: Container restarts (stability / crash-loop indicator)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "container_restarts" {
  name                = "alert-container-restarts"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    # isfuzzy=true: silently returns empty if the table doesn't exist yet
    # (fresh workspace before Container App has sent any logs)
    query = <<-KQL
      union isfuzzy=true ContainerAppSystemLogs_CL
      | where RevisionName_s contains "ca-gitea"
      | where Log_s contains "OOMKilled" or Log_s contains "CrashLoopBackOff" or Log_s contains "Restarting"
      | summarize count() by bin(TimeGenerated, 5m)
    KQL

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}

# Alert 2: Failed login attempts
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_logins" {
  name                = "alert-failed-logins"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query = <<-KQL
      union isfuzzy=true ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "ca-gitea"
      | where Log_s contains "Failed" and Log_s contains "login"
      | summarize FailedLogins = count() by bin(TimeGenerated, 5m)
      | where FailedLogins >= 5
    KQL

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}

# Alert 3: Suspicious access (non-OIDC login when OIDC is enforced)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "local_auth_attempt" {
  name                = "alert-local-auth-attempt"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1

  criteria {
    query = <<-KQL
      union isfuzzy=true ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "ca-gitea"
      | where Log_s contains "signin" and Log_s !contains "oauth2"
      | summarize count() by bin(TimeGenerated, 5m)
    KQL

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}

# Alert 4: Abnormal traffic (high request rate)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "abnormal_traffic" {
  name                = "alert-abnormal-traffic"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query = <<-KQL
      union isfuzzy=true ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "ca-gitea"
      | summarize Requests = count() by bin(TimeGenerated, 1m)
      | where Requests > 500
    KQL

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}
