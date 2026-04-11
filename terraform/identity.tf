# User Assigned Managed Identity — used by the Container App to access Key Vault
resource "azurerm_user_assigned_identity" "main" {
  name                = "id-${var.project}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}
# Note: Key Vault access is granted via access_policy blocks in keyvault.tf (not RBAC),
# so no azurerm_role_assignment is needed for Key Vault.
# Storage is mounted via shared access key (shared_access_key_enabled = true),
# so no RBAC role assignment is needed for the storage account either.
