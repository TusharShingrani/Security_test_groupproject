resource "azurerm_storage_account" "main" {
  name                     = local.sa_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Security hardening
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Required for Container Apps file mount

  tags = local.tags
}

# File share for Gitea persistent data (repos, DB, config)
resource "azurerm_storage_share" "gitea" {
  name                 = "gitea-data"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 10 # GB
}
