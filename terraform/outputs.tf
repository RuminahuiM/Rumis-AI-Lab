output "vm_ip" {
  description = "IP address of the frontend VM"
  value       = vsphere_virtual_machine.frontend.default_ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh rumis@${vsphere_virtual_machine.frontend.default_ip_address}"
}

output "open_webui_internal_url" {
  description = "Open WebUI URL (internal, before Azure App Proxy)"
  value       = "http://${vsphere_virtual_machine.frontend.default_ip_address}:3000"
}

output "n8n_internal_url" {
  description = "n8n URL (internal, before Azure App Proxy)"
  value       = "http://${vsphere_virtual_machine.frontend.default_ip_address}:5678"
}
