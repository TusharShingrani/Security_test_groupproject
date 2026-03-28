# ─── Network Security Group ───────────────────────────────────────────────────
# One NSG applied to all three VMs.
# Rules follow the principle of least privilege for this PoC.

resource "azurerm_network_security_group" "poc" {
  name                = "nsg-wss-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  # ── Inbound ──────────────────────────────────────────────────────────────

  # Allow SSH from reviewer/admin only (targets the Digital Twin public IP).
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

  # Allow WSS (8443) from within the VNet only – Digital Twin and Attacker
  # talk to the Agent over private IPs.
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

  # Allow SSH between VMs inside the VNet so the Digital Twin can hop to
  # the private VMs during the demo.
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

  # Deny all other inbound internet traffic explicitly.
  security_rule {
    name                       = "deny-inbound-internet"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # ── Outbound ─────────────────────────────────────────────────────────────
  # Allow all outbound so VMs can pull packages from apt/pypi on first boot.
  # In a tighter environment you would restrict this too.
  security_rule {
    name                       = "allow-outbound-all"
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
