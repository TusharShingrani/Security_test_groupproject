variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "bb1cb633-bb7e-44c4-b709-189e1cceee7e"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "norwayeast"
}

variable "resource_group_name" {
  description = "Resource group for this project"
  type        = string
  default     = "rg-gitea-sec"
}

variable "project" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "gitea-sec"
}

variable "gitea_admin_password" {
  description = "Gitea admin account password (stored in Key Vault)"
  type        = string
  sensitive   = true
}

variable "gitea_secret_key" {
  description = "Gitea internal secret key (random string, stored in Key Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitea_oidc_client_id" {
  description = "Entra ID app registration client ID for OIDC login"
  type        = string
  default     = ""
}

variable "gitea_oidc_client_secret" {
  description = "Entra ID OIDC client secret (stored in Key Vault)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tenant_id" {
  description = "Azure / Entra ID tenant ID (for Key Vault access policy)"
  type        = string
  default     = ""
}

variable "gitea_image" {
  description = "Gitea container image (rootless preferred)"
  type        = string
  default     = "gitea/gitea:1.21-rootless"
}

variable "container_cpu" {
  description = "CPU cores for Gitea container"
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memory for Gitea container (e.g. 1Gi)"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum container replicas (1 required for persistent storage)"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum container replicas"
  type        = number
  default     = 2
}
