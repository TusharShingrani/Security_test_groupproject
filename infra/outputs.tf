output "twin_public_ip" {
  description = "SSH into this IP to access the Digital Twin."
  value       = azurerm_public_ip.twin.ip_address
}

output "agent_private_ip" {
  value = azurerm_network_interface.agent.private_ip_address
}

output "attacker_private_ip" {
  value = azurerm_network_interface.attacker.private_ip_address
}

output "ssh_private_key_pem" {
  description = "SSH private key. Save locally with chmod 600."
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "ssh_connect" {
  description = "Command to SSH into the Digital Twin."
  value       = "ssh -i <(terraform output -raw ssh_private_key_pem) ${var.admin_username}@${azurerm_public_ip.twin.ip_address}"
}

output "auth_mode" {
  value = var.auth_mode
}
