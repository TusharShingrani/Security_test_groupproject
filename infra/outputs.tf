# ─── Outputs ──────────────────────────────────────────────────────────────────

output "dt_public_ip" {
  description = "Public IP of the Digital Twin VM – use this for SSH."
  value       = azurerm_public_ip.dt.ip_address
}

output "dt_private_ip" {
  description = "Private IP of the Digital Twin VM."
  value       = azurerm_network_interface.dt.private_ip_address
}

output "agent_private_ip" {
  description = "Private IP of the Software Agent VM."
  value       = azurerm_network_interface.agent.private_ip_address
}

output "attacker_private_ip" {
  description = "Private IP of the Attacker VM."
  value       = azurerm_network_interface.attacker.private_ip_address
}

output "agent_public_ip" {
  description = "Public IP of the Agent VM (only set when enable_public_ip_all=true)."
  value       = var.enable_public_ip_all ? azurerm_public_ip.agent[0].ip_address : "N/A (private only)"
}

output "attacker_public_ip" {
  description = "Public IP of the Attacker VM (only set when enable_public_ip_all=true)."
  value       = var.enable_public_ip_all ? azurerm_public_ip.attacker[0].ip_address : "N/A (private only)"
}

output "ssh_private_key_pem" {
  description = "SSH private key (PEM). Save to a file and chmod 600. Injected into the Digital Twin automatically."
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "ssh_connect_command" {
  description = "SSH command to log into the Digital Twin."
  value       = "ssh -i <(terraform output -raw ssh_private_key_pem) ${var.admin_username}@${azurerm_public_ip.dt.ip_address}"
}

output "auth_mode" {
  description = "Current AUTH_MODE deployed to the Agent."
  value       = var.auth_mode
}
