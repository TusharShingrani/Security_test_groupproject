# Random suffixes for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Current Azure client (used for Key Vault access policy)
data "azurerm_client_config" "current" {}

locals {
  tags = {
    project = var.project
    env     = "demo"
    managed = "terraform"
  }

  kv_name = "kv-gitea-${random_string.suffix.result}"
  sa_name = "sagitea${random_string.suffix.result}"
}
