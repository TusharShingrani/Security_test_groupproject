# ─── Read app source files into locals ───────────────────────────────────────
# We embed the Python files and systemd units into cloud-init so the VMs
# are fully configured on first boot without any post-deploy SCP.

locals {
  agent_py   = file("${path.module}/../app/agent.py")
  twin_py    = file("${path.module}/../app/twin.py")
  attacker_py = file("${path.module}/../app/attacker.py")
  common_py  = file("${path.module}/../app/common.py")
  requirements_txt = file("${path.module}/../app/requirements.txt")

  agent_service    = file("${path.module}/../systemd/software-agent.service")
  twin_service     = file("${path.module}/../systemd/digital-twin.service")
  attacker_service = file("${path.module}/../systemd/attacker.service")
}

# ─── Cloud-init user data ─────────────────────────────────────────────────────

data "template_file" "dt_cloud_init" {
  template = file("${path.module}/cloud-init/digital-twin.yaml.tftpl")

  vars = {
    agent_private_ip = "10.0.1.20"
    wss_port         = var.wss_port
    auth_mode        = var.auth_mode
    schedule_token   = var.schedule_token

    # App files
    twin_py          = local.twin_py
    common_py        = local.common_py
    requirements_txt = local.requirements_txt
    twin_service     = local.twin_service

    # SSH private key so DT can hop to private VMs
    ssh_private_key  = tls_private_key.ssh.private_key_openssh
    admin_username   = var.admin_username

    # Server cert for TLS verification
    server_cert_pem  = tls_self_signed_cert.agent_server.cert_pem
  }
}

data "template_file" "agent_cloud_init" {
  template = file("${path.module}/cloud-init/software-agent.yaml.tftpl")

  vars = {
    wss_port       = var.wss_port
    auth_mode      = var.auth_mode
    schedule_token = var.schedule_token

    # App files
    agent_py         = local.agent_py
    common_py        = local.common_py
    requirements_txt = local.requirements_txt
    agent_service    = local.agent_service

    # TLS server cert + key
    server_cert_pem = tls_self_signed_cert.agent_server.cert_pem
    server_key_pem  = tls_private_key.agent_server.private_key_pem
  }
}

data "template_file" "attacker_cloud_init" {
  template = file("${path.module}/cloud-init/attacker.yaml.tftpl")

  vars = {
    agent_private_ip = "10.0.1.20"
    wss_port         = var.wss_port

    # App files
    attacker_py      = local.attacker_py
    common_py        = local.common_py
    requirements_txt = local.requirements_txt
    attacker_service = local.attacker_service

    # Server cert for TLS verification
    server_cert_pem  = tls_self_signed_cert.agent_server.cert_pem
  }
}

# ─── VM: Digital Twin (dt-vm) ─────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "dt" {
  name                  = "dt-vm"
  location              = azurerm_resource_group.poc.location
  resource_group_name   = azurerm_resource_group.poc.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.dt.id]

  # Disable password auth – SSH key only
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

  custom_data = base64encode(data.template_file.dt_cloud_init.rendered)

  tags = { role = "digital-twin" }
}

# ─── VM: Software Agent (agent-vm) ────────────────────────────────────────────

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

  custom_data = base64encode(data.template_file.agent_cloud_init.rendered)

  tags = { role = "software-agent" }
}

# ─── VM: Attacker (attacker-vm) ───────────────────────────────────────────────

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

  custom_data = base64encode(data.template_file.attacker_cloud_init.rendered)

  tags = { role = "attacker" }
}
