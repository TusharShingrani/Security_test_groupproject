provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # When run from GitHub Actions with OIDC, ARM_USE_OIDC=true is set via
  # workflow env vars and the provider picks up the federated token automatically.
  # No client_secret is needed.
}
