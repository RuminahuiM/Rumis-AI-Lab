# ── vCenter Connection ────────────────────────────────────────────────────────

variable "vcenter_server" {
  type        = string
  description = "vCenter FQDN or IP"
}

variable "vcenter_username" {
  type        = string
  description = "vCenter SSO username"
}

variable "vcenter_password" {
  type        = string
  sensitive   = true
  description = "vCenter SSO password"
}

variable "vcenter_insecure" {
  type    = bool
  default = false
}

# ── vSphere Infrastructure ───────────────────────────────────────────────────

variable "datacenter" {
  type = string
}

variable "cluster" {
  type = string
}

variable "datastore" {
  type = string
}

variable "network" {
  type = string
}

variable "template_name" {
  type        = string
  default     = "rumis-ai-lab-template"
  description = "Name of the Packer-built VM template"
}

# ── VM Specs ─────────────────────────────────────────────────────────────────

variable "vm_name" {
  type    = string
  default = "rumis-ai-lab"
}

variable "vm_cpus" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type        = number
  default     = 8192
  description = "Memory in MB"
}

variable "vm_disk_size" {
  type        = number
  default     = 40
  description = "Disk size in GB"
}

# ── Application Config ───────────────────────────────────────────────────────

variable "nas_ip" {
  type        = string
  description = "Synology NAS IP for NFS mounts"
}

variable "nas_share_path" {
  type        = string
  default     = "/volume1/rumis-ai-lab"
  description = "NFS export path on Synology"
}

variable "vllm_endpoint" {
  type        = string
  description = "VLLM backend URL (e.g. http://192.168.1.200:8000)"
}

variable "oui_domain" {
  type        = string
  description = "Domain for Open WebUI (e.g. oui.mydomain.ch)"
}

variable "n8n_domain" {
  type        = string
  description = "Domain for n8n (e.g. n8n.mydomain.ch)"
}

variable "certbot_email" {
  type        = string
  description = "Email for Let's Encrypt notifications"
}

variable "postgres_user" {
  type    = string
  default = "rumis"
}

variable "postgres_password" {
  type      = string
  sensitive = true
}
