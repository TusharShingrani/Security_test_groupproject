resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ── Action Group ─────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "giteasec"
  tags                = local.tags
}

# ── Alert Rules (ARM template) ────────────────────────────────────────────────
# azurerm_monitor_scheduled_query_rules_alert_v2 validates KQL against the
# workspace schema at creation time. On a fresh workspace the Container App
# log tables (ContainerAppConsoleLogs_CL / ContainerAppSystemLogs_CL) don't
# exist yet, so the provider always errors. Using an ARM template deployment
# with skipQueryValidation=true bypasses this restriction.

resource "azurerm_resource_group_template_deployment" "monitor_alerts" {
  name                = "gitea-monitor-alerts"
  resource_group_name = azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  depends_on          = [azurerm_container_app_environment.main]

  parameters_content = jsonencode({
    workspaceId   = { value = azurerm_log_analytics_workspace.main.id }
    actionGroupId = { value = azurerm_monitor_action_group.main.id }
    location      = { value = var.location }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      workspaceId   = { type = "string" }
      actionGroupId = { type = "string" }
      location      = { type = "string" }
    }
    resources = [
      {
        type       = "microsoft.insights/scheduledqueryrules"
        apiVersion = "2023-03-15-preview"
        name       = "alert-container-restarts"
        location   = "[parameters('location')]"
        properties = {
          severity            = 2
          enabled             = true
          evaluationFrequency = "PT5M"
          windowSize          = "PT15M"
          skipQueryValidation = true
          scopes              = ["[parameters('workspaceId')]"]
          criteria = {
            allOf = [
              {
                query           = "ContainerAppSystemLogs_CL | where RevisionName_s contains 'ca-gitea' | where Log_s contains 'OOMKilled' or Log_s contains 'CrashLoopBackOff' or Log_s contains 'Restarting' | summarize count() by bin(TimeGenerated, 5m)"
                timeAggregation = "Count"
                operator        = "GreaterThanOrEqual"
                threshold       = 1
              }
            ]
          }
          actions = {
            actionGroups = ["[parameters('actionGroupId')]"]
          }
        }
      },
      {
        type       = "microsoft.insights/scheduledqueryrules"
        apiVersion = "2023-03-15-preview"
        name       = "alert-failed-logins"
        location   = "[parameters('location')]"
        properties = {
          severity            = 2
          enabled             = true
          evaluationFrequency = "PT5M"
          windowSize          = "PT15M"
          skipQueryValidation = true
          scopes              = ["[parameters('workspaceId')]"]
          criteria = {
            allOf = [
              {
                query           = "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'ca-gitea' | where Log_s contains 'Failed' and Log_s contains 'login' | summarize FailedLogins = count() by bin(TimeGenerated, 5m) | where FailedLogins >= 5"
                timeAggregation = "Count"
                operator        = "GreaterThanOrEqual"
                threshold       = 1
              }
            ]
          }
          actions = {
            actionGroups = ["[parameters('actionGroupId')]"]
          }
        }
      },
      {
        type       = "microsoft.insights/scheduledqueryrules"
        apiVersion = "2023-03-15-preview"
        name       = "alert-local-auth-attempt"
        location   = "[parameters('location')]"
        properties = {
          severity            = 1
          enabled             = true
          evaluationFrequency = "PT5M"
          windowSize          = "PT15M"
          skipQueryValidation = true
          scopes              = ["[parameters('workspaceId')]"]
          criteria = {
            allOf = [
              {
                query           = "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'ca-gitea' | where Log_s contains 'signin' and Log_s !contains 'oauth2' | summarize count() by bin(TimeGenerated, 5m)"
                timeAggregation = "Count"
                operator        = "GreaterThanOrEqual"
                threshold       = 1
              }
            ]
          }
          actions = {
            actionGroups = ["[parameters('actionGroupId')]"]
          }
        }
      },
      {
        type       = "microsoft.insights/scheduledqueryrules"
        apiVersion = "2023-03-15-preview"
        name       = "alert-abnormal-traffic"
        location   = "[parameters('location')]"
        properties = {
          severity            = 2
          enabled             = true
          evaluationFrequency = "PT5M"
          windowSize          = "PT15M"
          skipQueryValidation = true
          scopes              = ["[parameters('workspaceId')]"]
          criteria = {
            allOf = [
              {
                query           = "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'ca-gitea' | summarize Requests = count() by bin(TimeGenerated, 1m) | where Requests > 500"
                timeAggregation = "Count"
                operator        = "GreaterThanOrEqual"
                threshold       = 1
              }
            ]
          }
          actions = {
            actionGroups = ["[parameters('actionGroupId')]"]
          }
        }
      }
    ]
  })

  tags = local.tags
}
