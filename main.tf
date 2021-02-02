variable "server_name" {}
variable "vcpus" {}
variable "memory" {}
variable "template_name" {}
variable "linux_count" {
  default = 1
}
variable "datacenter" {
  default = "Datacenter"
}
variable "cluster" {
  default = "East"
}
variable "datastore" {
  default = "iaas57_dsc_svch8_nr_v6_rsc"
}
variable "network" {
  default = "VM Network"
}
variable "disk_size" {
  default = "20"
}
variable "domain" {}
variable "ipv4_address" {}
variable "ipv4_netmask" {}
variable "ipv4_gateway" {}
variable "linux_admin_password" {
  default = "automate!"
}
variable "username" {
  type = string
  description = "my_username"
  default = "AA"
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore_cluster" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template_name" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "linux_vm" {
  count                = var.linux_count
  name                 = "${var.server_name}-RHEL-${count.index}"
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  folder               = "TEST"
  datastore_cluster_id = data.vsphere_datastore_cluster.datastore.id

  num_cpus  = var.vcpus
  memory    = var.memory
  firmware  = "bios"
  guest_id  = data.vsphere_virtual_machine.template_name.guest_id
  scsi_type = data.vsphere_virtual_machine.template_name.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template_name.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template_name.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.template_name.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template_name.id
    customize {
      linux_options {
        host_name = "${var.server_name}-RHEL"
        domain    = var.domain
      }
      network_interface {
        ipv4_address = var.ipv4_address
        ipv4_netmask = var.ipv4_netmask
      }
      ipv4_gateway = var.ipv4_gateway
    }
  }
  # annotation = "Server built with Terraform - ${formatdate("DD MMM YYYY hh:mm ZZZ", timestamp())}"
  annotation = templatefile("${path.module}/templates/notes.tpl", {
    user_name     = var.username
    template_name = var.template_name
    cluster_name  = var.cluster
  })

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "student"
      password = var.linux_admin_password
      host     = self.default_ip_address
    }

    inline = [
      "cat /etc/os-release"
    ]

  }
  lifecycle {
    ignore_changes = [annotation]
  }
}

resource "null_resource" "cluster" {
  # Changes to the count of VMs requires re-provisioning
  triggers = {
    cluster_instance_ids = "${join(",", vsphere_virtual_machine.linux_vm.*.id)}"
  }

  # Bootstrap script can run on any VM
  connection {
    type     = "ssh"
    user     = "student"
    password = var.linux_admin_password
    host     = vsphere_virtual_machine.linux_vm[0].default_ip_address
  }

  provisioner "remote-exec" {
    # Production use-case could be a script called with private_ip of each node in the cluster
    # For lab purposes, print the current date & time and the kernel name & release
    inline = [
      "date && uname -sr"
    ]
  }
}

output "linux_server_name" {
  value = vsphere_virtual_machine.linux_vm[*].name
}

output "linux_server_memory" {
  value = vsphere_virtual_machine.linux_vm[*].memory
}

output "linux_ip_address" {
  value = vsphere_virtual_machine.linux_vm[*].default_ip_address
}
