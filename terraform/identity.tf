# User Assigned Managed Identity — used by the Container App to access Key Vault
resource "azurerm_user_assigned_identity" "main" {
  name                = "id-${var.project}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# Key Vault Secrets User — allows the identity to read secrets
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Storage File Data SMB Share Contributor — allows Azure Files mount
resource "azurerm_role_assignment" "storage_smb" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
