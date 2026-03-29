resource "azurerm_virtual_network" "poc" {
  name                = "vnet-wss-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  address_space       = [var.vnet_address_space]
}

resource "azurerm_subnet" "poc" {
  name                 = "snet-poc"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.poc.name
  address_prefixes     = [var.subnet_prefix]
}

# ── Public IPs ────────────────────────────────────────────────────────────────
# Only the Digital Twin gets a public IP by default.
# Standard SKU required - Basic SKU is restricted on student subscriptions.

resource "azurerm_public_ip" "twin" {
  name                = "pip-twin"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "agent" {
  count               = var.enable_public_ip_all ? 1 : 0
  name                = "pip-agent"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "attacker" {
  count               = var.enable_public_ip_all ? 1 : 0
  name                = "pip-attacker"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ── NICs ─────────────────────────────────────────────────────────────────────

resource "azurerm_network_interface" "twin" {
  name                = "nic-twin"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.poc.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
    public_ip_address_id          = azurerm_public_ip.twin.id
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

# ── NSG associations ─────────────────────────────────────────────────────────

resource "azurerm_network_interface_security_group_association" "twin" {
  network_interface_id      = azurerm_network_interface.twin.id
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
