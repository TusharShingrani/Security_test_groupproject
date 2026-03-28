# ─── Azure ───────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  default     = "bb1cb633-bb7e-44c4-b709-189e1cceee7e"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group that will be created."
  type        = string
  default     = "rg-wss-poc"
}

# ─── Network ─────────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "Address prefix for the single subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into the Digital Twin public IP. Set to your workstation IP, e.g. 1.2.3.4/32."
  type        = string
  # Wide-open default so the pipeline can deploy without extra config.
  # Reviewers should restrict this to their own IP.
  default = "0.0.0.0/0"
}

# ─── Compute ─────────────────────────────────────────────────────────────────

variable "vm_size" {
  description = "VM SKU for all three VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "ubuntu_image" {
  description = "Ubuntu LTS image reference (publisher/offer/sku)."
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

variable "admin_username" {
  description = "OS admin username for all VMs."
  type        = string
  default     = "azureuser"
}

# ─── Cost / troubleshooting toggle ───────────────────────────────────────────

variable "enable_public_ip_all" {
  description = "Set to true to give all three VMs a public IP (useful for troubleshooting). Default is false – only the Digital Twin gets a public IP."
  type        = bool
  default     = false
}

# ─── App ─────────────────────────────────────────────────────────────────────

variable "auth_mode" {
  description = "Auth mode passed to the Software Agent: 'none' (insecure demo) or 'token' (fixed demo)."
  type        = string
  default     = "none"
}

variable "schedule_token" {
  description = "Shared secret used when AUTH_MODE=token. Not required in 'none' mode."
  type        = string
  default     = "changeme-super-secret-token"
  sensitive   = true
}

variable "wss_port" {
  description = "Port the Software Agent WSS server listens on."
  type        = number
  default     = 8443
}
