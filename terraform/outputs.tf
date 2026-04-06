output "gitea_url" {
  description = "Gitea application URL"
  value       = "https://${azurerm_container_app.gitea.ingress[0].fqdn}"
}

output "gitea_fqdn" {
  description = "Gitea FQDN (use this in Entra ID app registration redirect URI)"
  value       = azurerm_container_app.gitea.ingress[0].fqdn
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "key_vault_name" {
  description = "Key Vault name (random suffix applied)"
  value       = azurerm_key_vault.main.name
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "managed_identity_client_id" {
  description = "Client ID of the managed identity (use in Gitea OIDC config)"
  value       = azurerm_user_assigned_identity.main.client_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID"
  value       = azurerm_log_analytics_workspace.main.id
}

output "entra_oidc_setup" {
  description = "Steps to complete Entra ID OIDC integration"
  value       = <<-EOT
    1. Go to Azure Portal → Entra ID → App Registrations → New Registration
    2. Name: gitea-oidc
    3. Redirect URI: https://${azurerm_container_app.gitea.ingress[0].fqdn}/user/oauth2/EntraID/callback
    4. Create client secret → store in Key Vault secret 'gitea-oidc-client-secret'
    5. In Gitea (admin panel) → Authentication Sources → Add OAuth2:
       Provider: OpenID Connect
       Discovery URL: https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
       Client ID: <app-registration-client-id>
       Client Secret: <from Key Vault>
  EOT
}
