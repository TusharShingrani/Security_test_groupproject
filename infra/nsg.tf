resource "azurerm_network_security_group" "poc" {
  name                = "nsg-wss-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  # Allow SSH from admin only (targets Digital Twin public IP)
  security_rule {
    name                       = "allow-ssh-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  # Allow WSS (8443) from within the VNet
  security_rule {
    name                       = "allow-wss-vnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.wss_port)
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow SSH between VMs for hop access
  security_rule {
    name                       = "allow-ssh-vnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Block all other internet inbound
  security_rule {
    name                       = "deny-internet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow all outbound so VMs can pull packages on first boot
  security_rule {
    name                       = "allow-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
