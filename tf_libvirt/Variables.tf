locals {
    cloud_image = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    #cloud_image = "../../../images/ubuntu/focal-server-cloudimg-amd64.img"

    # Virtual Machines
    VMs = toset(["k8scpnode1", "k8swrknode1", "k8swrknode2"])

    # TimeZone of the VM: /usr/share/zoneinfo/
    timezone    = "Africa/Tunis"

    # The sshd port of the VM"
    ssh_port    = 22

    # The default ssh key for user ubuntu
    # https://github.com/<username>.keys
    gh_user = "bios"

    # The disk volume size of the VM
    # eg. 40G
    vol_size = 20 * 1024 * 1024 * 1024

    # How many virtual CPUs the VM
    vcpu = 2

    # How RAM will VM have will have
    vmem = 2048
}
