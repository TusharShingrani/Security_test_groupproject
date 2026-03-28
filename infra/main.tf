terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {}
}

# ── Resource group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "poc" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "wss-poc"
    env     = "demo"
  }
}

# ── SSH key pair ──────────────────────────────────────────────────────────────

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
