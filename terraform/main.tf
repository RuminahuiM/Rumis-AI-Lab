terraform {
  required_version = ">= 1.5"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.9"
    }
  }
}

provider "vsphere" {
  user                 = var.vcenter_username
  password             = var.vcenter_password
  vsphere_server       = var.vcenter_server
  allow_unverified_ssl = var.vcenter_insecure
}

# ── Data sources ─────────────────────────────────────────────────────────────

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# ── Cloud-init ───────────────────────────────────────────────────────────────

locals {
  cloud_init_userdata = templatefile("${path.module}/templates/cloud-init.yaml", {
    vllm_endpoint           = var.vllm_endpoint
    azure_tenant_id         = var.azure_tenant_id
    oauth_client_id         = var.oauth_client_id
    oauth_client_secret     = var.oauth_client_secret
    oauth_client_id_n8n     = var.oauth_client_id_n8n
    oauth_client_secret_n8n = var.oauth_client_secret_n8n
    webui_admin_email       = var.webui_admin_email
    webui_admin_password    = var.webui_admin_password
    litellm_master_key      = var.litellm_master_key
    github_pat              = var.github_pat
    git_branch              = var.git_branch
    ssh_authorized_keys     = var.ssh_authorized_keys
    anthropic_api_key       = var.anthropic_api_key
    openai_api_key          = var.openai_api_key
    gemini_api_key          = var.gemini_api_key
  })
}

# ── VM ───────────────────────────────────────────────────────────────────────

resource "vsphere_virtual_machine" "frontend" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.vm_cpus
  memory   = var.vm_memory

  guest_id = data.vsphere_virtual_machine.template.guest_id

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # OS disk
  disk {
    label            = "disk0"
    size             = var.vm_disk_size
    thin_provisioned = true
  }

  # OpenWebUI data disk
  disk {
    label            = "openwebui-data"
    size             = var.openwebui_disk_size
    unit_number      = 1
    thin_provisioned = true
  }

  # n8n data disk
  disk {
    label            = "n8n-data"
    size             = var.n8n_disk_size
    unit_number      = 2
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.userdata"          = base64encode(local.cloud_init_userdata)
    "guestinfo.userdata.encoding" = "base64"
    "guestinfo.metadata"          = base64encode("{\"instance-id\": \"${var.vm_name}\", \"local-hostname\": \"${var.vm_name}\"}")
    "guestinfo.metadata.encoding" = "base64"
  }

  lifecycle {
    ignore_changes = [
      extra_config,
    ]
  }
}
