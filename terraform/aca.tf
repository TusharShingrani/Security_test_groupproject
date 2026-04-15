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
# Architecture: Internet → WAF sidecar (port 8080) → Gitea (localhost:3000)
# The ingress target_port points at the WAF. ModSecurity inspects every request
# before it reaches Gitea, blocking SQLi, XSS, path traversal, and other OWASP
# CRS rule matches. Both containers share the same network namespace so the
# WAF reaches Gitea via localhost.
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
    name  = "storage-key"
    value = azurerm_storage_account.main.primary_access_key
  }

  # All external traffic enters on port 8080 (WAF) — not directly on Gitea port 3000
  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Azure Files (SMB) share — persistent repos, avatars, attachments, logs
    volume {
      name         = "gitea-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.gitea.name
    }

    # Local ephemeral volume for SQLite DB — Azure Files SMB does not support
    # the POSIX fcntl() advisory locks that SQLite requires, so the DB must
    # live on local storage. Data is lost on container restart (PoC trade-off).
    volume {
      name         = "gitea-db"
      storage_type = "EmptyDir"
    }

    # ── WAF sidecar — NGINX + ModSecurity + OWASP CRS ──────────────────────
    # Listens on port 8080, proxies clean requests to localhost:3000 (Gitea).
    # Blocks requests that match OWASP CRS rules (SQLi, XSS, path traversal,
    # known scanner user-agents, Log4Shell, etc.) before they reach Gitea.
    container {
      name   = "waf"
      image  = "owasp/modsecurity-crs:nginx-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      # Proxy to Gitea on localhost (shared network namespace)
      env {
        name  = "BACKEND"
        value = "http://localhost:3000"
      }

      # Blocking mode — requests matching OWASP CRS rules return 403
      env {
        name  = "MODSEC_RULE_ENGINE"
        value = "On"
      }

      # Paranoia level 1 (CRS default) — low false-positive rate
      env {
        name  = "PARANOIA"
        value = "1"
      }

      # Inbound anomaly score threshold: 5 (CRS default)
      env {
        name  = "ANOMALY_INBOUND"
        value = "5"
      }

      # Listen on port 8080 (non-root compatible)
      env {
        name  = "PORT"
        value = "8080"
      }

      # Allow larger request bodies for git push payloads
      env {
        name  = "MODSEC_REQ_BODY_LIMIT"
        value = "52428800"
      }

      env {
        name  = "NGINX_CLIENT_MAX_BODY_SIZE"
        value = "50m"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 8080

        initial_delay           = 15
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 8080

        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }

    # ── Gitea container ─────────────────────────────────────────────────────
    # Listens on port 3000 — internal only, not exposed via ingress.
    # All external traffic passes through the WAF sidecar above.
    container {
      name   = "gitea"
      image  = var.gitea_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Gitea configuration via environment variables
      # Rootless image runs as UID 1000, data at /var/lib/gitea
      env {
        name  = "GITEA__server__DOMAIN"
        value = "ca-gitea.${azurerm_container_app_environment.main.default_domain}"
      }

      env {
        name  = "GITEA__server__ROOT_URL"
        value = "https://ca-gitea.${azurerm_container_app_environment.main.default_domain}"
      }

      env {
        name  = "GITEA__security__INSTALL_LOCK"
        value = "true"
      }

      env {
        name  = "GITEA__git__HOME_PATH"
        value = "/tmp/gitea-home"
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

      # DB on local EmptyDir — POSIX locks work here (unlike Azure Files SMB)
      env {
        name  = "GITEA__database__PATH"
        value = "/gitea-db/gitea.db"
      }

      env {
        name        = "GITEA__security__SECRET_KEY"
        secret_name = "gitea-secret-key"
      }

      # ── Session hardening ────────────────────────────────────────────────
      # COOKIE_SECURE: session cookie is only sent over HTTPS, never plain HTTP.
      # A stolen cookie cannot be replayed over an unencrypted channel.
      env {
        name  = "GITEA__session__COOKIE_SECURE"
        value = "true"
      }

      # SAME_SITE=lax: browser only sends cookie on same-site navigations and
      # top-level GET cross-site navigations. Blocks CSRF attacks that rely on
      # the browser auto-submitting the session cookie to a third-party origin.
      env {
        name  = "GITEA__session__SAME_SITE"
        value = "lax"
      }

      # SESSION_LIFE_TIME: session expires after 1 hour of total age.
      # Limits the window in which a stolen cookie can be replayed.
      # Default is 86400 (24 h) — too long for an admin-only platform.
      env {
        name  = "GITEA__session__SESSION_LIFE_TIME"
        value = "3600"
      }

      # ── Reverse proxy trust ──────────────────────────────────────────────
      # Gitea is behind the WAF sidecar on localhost. Without this, Gitea
      # sees 127.0.0.1 as every client IP, which breaks rate-limiting and
      # audit logs. REVERSE_PROXY_LIMIT=1 tells Gitea to trust one proxy hop
      # and read the real client IP from X-Forwarded-For.
      env {
        name  = "GITEA__security__REVERSE_PROXY_LIMIT"
        value = "1"
      }

      env {
        name  = "GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES"
        value = "127.0.0.1/8"
      }

      env {
        name  = "GITEA__log__LEVEL"
        value = "Info"
      }

      env {
        name  = "GITEA__log__ROOT_PATH"
        value = "/var/lib/gitea/log"
      }

      # Queue data on local tmpfs — Azure Files SMB does not support the POSIX
      # permissions required by LevelDB (the queue backing store). Moving queues
      # to /tmp mirrors the same fix applied to the SQLite DB (EmptyDir).
      # Queue data is ephemeral by design; Gitea re-initialises queues on startup.
      env {
        name  = "GITEA__queue__DATADIR"
        value = "/tmp/gitea-queues"
      }

      # Azure Files mount — repos, avatars, attachments, logs
      volume_mounts {
        name = "gitea-data"
        path = "/var/lib/gitea"
      }

      # EmptyDir mount — SQLite database only
      volume_mounts {
        name = "gitea-db"
        path = "/gitea-db"
      }

      # Liveness probe — checks Gitea directly on its internal port
      liveness_probe {
        transport = "HTTP"
        path      = "/"
        port      = 3000

        initial_delay           = 30
        interval_seconds        = 30
        failure_count_threshold = 3
      }

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
  ]
}
