packer {
  required_plugins {
    vsphere = {
      version = ">= 1.4.0"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}

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

variable "iso_path" {
  type        = string
  description = "Datastore path to Ubuntu 24.04 ISO (e.g. [datastore1] iso/ubuntu-24.04.2-live-server-amd64.iso)"
}

variable "vm_name" {
  type    = string
  default = "rumis-ai-lab-template"
}

variable "vm_cpus" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type    = number
  default = 8192
}

variable "vm_disk_size" {
  type    = number
  default = 40960
}

variable "ssh_username" {
  type    = string
  default = "rumis"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "rumis-packer-build"
}

source "vsphere-iso" "ubuntu" {
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_username
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure

  datacenter = var.datacenter
  cluster    = var.cluster
  datastore  = var.datastore

  vm_name              = var.vm_name
  guest_os_type        = "ubuntu64Guest"
  CPUs                 = var.vm_cpus
  RAM                  = var.vm_memory
  RAM_reserve_all      = false
  disk_controller_type = ["pvscsi"]

  storage {
    disk_size             = var.vm_disk_size
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.network
    network_card = "vmxnet3"
  }

  iso_paths = [var.iso_path]

  http_directory = "http"

  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ",
    "<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = "5s"

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  convert_to_template = true
}

build {
  sources = ["source.vsphere-iso.ubuntu"]

  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S bash '{{ .Path }}'"
    scripts = [
      "scripts/setup.sh"
    ]
  }
}
