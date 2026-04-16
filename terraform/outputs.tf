output "vm_ip" {
  description = "IP address of the frontend VM"
  value       = vsphere_virtual_machine.frontend.default_ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh rumis@${vsphere_virtual_machine.frontend.default_ip_address}"
}

output "open_webui_url" {
  description = "Open WebUI URL (after SSL setup)"
  value       = "https://${var.oui_domain}"
}

output "n8n_url" {
  description = "n8n URL (after SSL setup)"
  value       = "https://${var.n8n_domain}"
}
