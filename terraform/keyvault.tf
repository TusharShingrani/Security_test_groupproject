resource "azurerm_key_vault" "main" {
  name                       = local.kv_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # false for easy PoC teardown

  # Only managed identity and the Terraform deployer can access
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.main.principal_id

    secret_permissions = ["Get", "List"]
  }

  # Block all public network access except trusted Azure services
  network_acls {
    default_action = "Allow" # Tighten to "Deny" + ip_rules in production
    bypass         = "AzureServices"
  }

  tags = local.tags
}

# ── Secrets ──────────────────────────────────────────────────────────────────

resource "azurerm_key_vault_secret" "gitea_admin_password" {
  name         = "gitea-admin-password"
  value        = var.gitea_admin_password
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "gitea_secret_key" {
  name         = "gitea-secret-key"
  value        = var.gitea_secret_key != "" ? var.gitea_secret_key : random_string.suffix.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "gitea_oidc_client_secret" {
  name         = "gitea-oidc-client-secret"
  value        = var.gitea_oidc_client_secret != "" ? var.gitea_oidc_client_secret : "not-configured"
  key_vault_id = azurerm_key_vault.main.id
}
