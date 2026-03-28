# ─── Virtual Network ─────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "poc" {
  name                = "vnet-wss-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  address_space       = [var.vnet_address_space]
}

# ─── Subnet ──────────────────────────────────────────────────────────────────

resource "azurerm_subnet" "poc" {
  name                 = "snet-poc"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.poc.name
  address_prefixes     = [var.subnet_prefix]
}

# ─── Public IPs ──────────────────────────────────────────────────────────────
# By default only the Digital Twin gets a public IP.
# Set enable_public_ip_all=true to get public IPs on all VMs (troubleshooting).

resource "azurerm_public_ip" "dt" {
  name                = "pip-dt"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_public_ip" "agent" {
  count               = var.enable_public_ip_all ? 1 : 0
  name                = "pip-agent"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_public_ip" "attacker" {
  count               = var.enable_public_ip_all ? 1 : 0
  name                = "pip-attacker"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Basic"
}

# ─── NICs ────────────────────────────────────────────────────────────────────

resource "azurerm_network_interface" "dt" {
  name                = "nic-dt"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.poc.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
    public_ip_address_id          = azurerm_public_ip.dt.id
  }
}

resource "azurerm_network_interface" "agent" {
  name                = "nic-agent"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.poc.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.20"
    public_ip_address_id          = var.enable_public_ip_all ? azurerm_public_ip.agent[0].id : null
  }
}

resource "azurerm_network_interface" "attacker" {
  name                = "nic-attacker"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.poc.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.30"
    public_ip_address_id          = var.enable_public_ip_all ? azurerm_public_ip.attacker[0].id : null
  }
}

# ─── NSG associations ────────────────────────────────────────────────────────

resource "azurerm_network_interface_security_group_association" "dt" {
  network_interface_id      = azurerm_network_interface.dt.id
  network_security_group_id = azurerm_network_security_group.poc.id
}

resource "azurerm_network_interface_security_group_association" "agent" {
  network_interface_id      = azurerm_network_interface.agent.id
  network_security_group_id = azurerm_network_security_group.poc.id
}

resource "azurerm_network_interface_security_group_association" "attacker" {
  network_interface_id      = azurerm_network_interface.attacker.id
  network_security_group_id = azurerm_network_security_group.poc.id
}
