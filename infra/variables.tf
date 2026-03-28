# ── Azure ─────────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  default     = "bb1cb633-bb7e-44c4-b709-189e1cceee7e"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group to create."
  type        = string
  default     = "rg-wss-poc"
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into the Digital Twin public IP."
  type        = string
  default     = "0.0.0.0/0"
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ubuntu_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# ── Cost toggle ───────────────────────────────────────────────────────────────

variable "enable_public_ip_all" {
  description = "Give all VMs a public IP (troubleshooting only). Default false."
  type        = bool
  default     = false
}

# ── App ───────────────────────────────────────────────────────────────────────

variable "auth_mode" {
  description = "AUTH_MODE passed to agent: 'none' or 'token'."
  type        = string
  default     = "none"
}

variable "schedule_token" {
  description = "Shared secret used when AUTH_MODE=token."
  type        = string
  default     = "changeme-token"
  sensitive   = true
}

variable "wss_port" {
  type    = number
  default = 8443
}
