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
    nas_ip         = var.nas_ip
    nas_share_path = var.nas_share_path
    oui_domain     = var.oui_domain
    n8n_domain     = var.n8n_domain
    certbot_email  = var.certbot_email
    postgres_user  = var.postgres_user
    postgres_pass  = var.postgres_password
    vllm_endpoint  = var.vllm_endpoint
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

  disk {
    label            = "disk0"
    size             = var.vm_disk_size
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
