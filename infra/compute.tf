locals {
  agent_py         = file("${path.module}/../app/agent.py")
  twin_py          = file("${path.module}/../app/twin.py")
  attacker_py      = file("${path.module}/../app/attacker.py")
  requirements_txt = file("${path.module}/../app/requirements.txt")

  agent_service    = file("${path.module}/../systemd/agent.service")
  twin_service     = file("${path.module}/../systemd/twin.service")
  attacker_service = file("${path.module}/../systemd/attacker.service")
}

# ── Cloud-init rendering ──────────────────────────────────────────────────────

data "template_file" "twin_init" {
  template = file("${path.module}/cloud-init/twin.yaml.tftpl")
  vars = {
    agent_private_ip = "10.0.1.20"
    wss_port         = var.wss_port
    auth_mode        = var.auth_mode
    schedule_token   = var.schedule_token
    twin_py          = local.twin_py
    requirements_txt = local.requirements_txt
    twin_service     = local.twin_service
    server_cert_pem  = tls_self_signed_cert.agent_server.cert_pem
    ssh_private_key  = tls_private_key.ssh.private_key_openssh
    admin_username   = var.admin_username
  }
}

data "template_file" "agent_init" {
  template = file("${path.module}/cloud-init/agent.yaml.tftpl")
  vars = {
    wss_port         = var.wss_port
    auth_mode        = var.auth_mode
    schedule_token   = var.schedule_token
    agent_py         = local.agent_py
    requirements_txt = local.requirements_txt
    agent_service    = local.agent_service
    server_cert_pem  = tls_self_signed_cert.agent_server.cert_pem
    server_key_pem   = tls_private_key.agent_server.private_key_pem
  }
}

data "template_file" "attacker_init" {
  template = file("${path.module}/cloud-init/attacker.yaml.tftpl")
  vars = {
    agent_private_ip = "10.0.1.20"
    wss_port         = var.wss_port
    attacker_py      = local.attacker_py
    requirements_txt = local.requirements_txt
    attacker_service = local.attacker_service
    server_cert_pem  = tls_self_signed_cert.agent_server.cert_pem
  }
}

# ── VM: Digital Twin ──────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "twin" {
  name                  = "twin-vm"
  location              = azurerm_resource_group.poc.location
  resource_group_name   = azurerm_resource_group.poc.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.twin.id]

  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = var.ubuntu_image.publisher
    offer     = var.ubuntu_image.offer
    sku       = var.ubuntu_image.sku
    version   = var.ubuntu_image.version
  }

  custom_data = base64encode(data.template_file.twin_init.rendered)
  tags        = { role = "digital-twin" }
}

# ── VM: Software Agent ────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "agent" {
  name                  = "agent-vm"
  location              = azurerm_resource_group.poc.location
  resource_group_name   = azurerm_resource_group.poc.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.agent.id]

  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = var.ubuntu_image.publisher
    offer     = var.ubuntu_image.offer
    sku       = var.ubuntu_image.sku
    version   = var.ubuntu_image.version
  }

  custom_data = base64encode(data.template_file.agent_init.rendered)
  tags        = { role = "software-agent" }
}

# ── VM: Attacker ──────────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "attacker" {
  name                  = "attacker-vm"
  location              = azurerm_resource_group.poc.location
  resource_group_name   = azurerm_resource_group.poc.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.attacker.id]

  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = var.ubuntu_image.publisher
    offer     = var.ubuntu_image.offer
    sku       = var.ubuntu_image.sku
    version   = var.ubuntu_image.version
  }

  custom_data = base64encode(data.template_file.attacker_init.rendered)
  tags        = { role = "attacker" }
}
