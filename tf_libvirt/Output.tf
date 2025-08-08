output "VMs" {
  value = [ for vms in libvirt_domain.domain-ubuntu : format("%s  %s", vms.network_interface.0.addresses[0], vms.name) ]

  depends_on = [libvirt_domain.domain-ubuntu]
}

# Generate inventory.ini file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    control_nodes = [
      for vm in libvirt_domain.domain-ubuntu : {
        name = vm.name
        ip   = vm.network_interface.0.addresses[0]
      }
      if can(regex("k8scpnode", vm.name))
    ]
    worker_nodes = [
      for vm in libvirt_domain.domain-ubuntu : {
        name = vm.name
        ip   = vm.network_interface.0.addresses[0]
      }
      if can(regex("k8swrknode", vm.name))
    ]
  })
  filename = "${path.module}/../inventory.ini"
  depends_on = [libvirt_domain.domain-ubuntu]
}

