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
  description = "OS disk size in GB"
}

variable "openwebui_disk_size" {
  type        = number
  default     = 20
  description = "OpenWebUI data disk size in GB"
}

variable "n8n_disk_size" {
  type        = number
  default     = 10
  description = "n8n data disk size in GB"
}

# ── VLLM Backend ─────────────────────────────────────────────────────────────

variable "vllm_endpoint" {
  type        = string
  description = "VLLM backend URL (e.g. http://192.168.1.200:8000)"
}

# ── Azure AD SSO ─────────────────────────────────────────────────────────────

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID"
}

variable "oauth_client_id" {
  type        = string
  description = "Azure AD App Registration client ID for OpenWebUI"
}

variable "oauth_client_secret" {
  type        = string
  sensitive   = true
  description = "Azure AD App Registration client secret for OpenWebUI"
}

variable "oauth_client_id_n8n" {
  type        = string
  description = "Azure AD App Registration client ID for n8n"
}

variable "oauth_client_secret_n8n" {
  type        = string
  sensitive   = true
  description = "Azure AD App Registration client secret for n8n"
}

# ── Application Config ───────────────────────────────────────────────────────

variable "webui_admin_email" {
  type        = string
  default     = "admin@example.com"
  description = "Open WebUI admin email (created on first boot)"
}

variable "webui_admin_password" {
  type        = string
  sensitive   = true
  description = "Open WebUI admin password"
}

variable "litellm_master_key" {
  type        = string
  sensitive   = true
  default     = "sk-rumis-litellm-master"
  description = "LiteLLM proxy master key"
}
