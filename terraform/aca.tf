# Container Apps Environment (Consumption plan — lowest cost)
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# Mount the Azure Files share into the Container Apps Environment
resource "azurerm_container_app_environment_storage" "gitea" {
  name                         = "gitea-data"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.gitea.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

# Gitea Container App
resource "azurerm_container_app" "gitea" {
  name                         = "ca-gitea"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags

  # Attach managed identity so Key Vault references work
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  # Key Vault secret references (pulled at runtime via managed identity)
  secret {
    name                = "gitea-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.gitea_admin_password.id
    identity            = azurerm_user_assigned_identity.main.id
  }

  secret {
    name                = "gitea-secret-key"
    key_vault_secret_id = azurerm_key_vault_secret.gitea_secret_key.id
    identity            = azurerm_user_assigned_identity.main.id
  }

  secret {
    name                = "storage-key"
    value               = azurerm_storage_account.main.primary_access_key
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    volume {
      name         = "gitea-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.gitea.name
    }

    container {
      name   = "gitea"
      image  = var.gitea_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Gitea configuration via environment variables
      # Rootless image runs as UID 1000, data at /var/lib/gitea
      env {
        name  = "GITEA__server__DOMAIN"
        value = azurerm_container_app.gitea.ingress[0].fqdn
      }

      env {
        name  = "GITEA__server__ROOT_URL"
        value = "https://${azurerm_container_app.gitea.ingress[0].fqdn}"
      }

      env {
        name  = "GITEA__server__DISABLE_SSH"
        value = "true"
      }

      env {
        name  = "GITEA__server__START_SSH_SERVER"
        value = "false"
      }

      env {
        name  = "GITEA__service__DISABLE_REGISTRATION"
        value = "true"
      }

      env {
        name  = "GITEA__service__REQUIRE_SIGNIN_VIEW"
        value = "true"
      }

      env {
        name  = "GITEA__database__DB_TYPE"
        value = "sqlite3"
      }

      env {
        name  = "GITEA__database__PATH"
        value = "/var/lib/gitea/data/gitea.db"
      }

      env {
        name        = "GITEA__security__SECRET_KEY"
        secret_name = "gitea-secret-key"
      }

      env {
        name  = "GITEA__log__LEVEL"
        value = "Info"
      }

      env {
        name  = "GITEA__log__ROOT_PATH"
        value = "/var/lib/gitea/log"
      }

      # Volume mount for persistent storage
      volume_mounts {
        name = "gitea-data"
        path = "/var/lib/gitea"
      }

      # Liveness probe
      liveness_probe {
        transport = "HTTP"
        path      = "/"
        port      = 3000

        initial_delay           = 30
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      # Readiness probe
      readiness_probe {
        transport = "HTTP"
        path      = "/"
        port      = 3000

        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  depends_on = [
    azurerm_container_app_environment_storage.gitea,
    azurerm_role_assignment.kv_secrets_user,
  ]
}
