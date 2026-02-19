packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "archives_directory" {
  type = string
  default = "/data/nfsshare/archives/"
}

variable "vm_template_name" {
  type    = string
  default = "packer-uefi-u2404.qcow2"
}

variable "ubuntu_iso_file" {
  type    = string
  default = "ubuntu-24.04.4-live-server-amd64.iso"
}

variable "LINBIT_KEY" {
  type    = string
  default = "undefined"
}

source "qemu" "custom_image" {
  
  boot_command = [
    "<spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " noapic<wait>",
    " nohpet<wait>",
    " vga=0<wait>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    " locale=en_US<wait>",
    " console-setup/ask_detect=false<wait>",
    " console-setup/layoutcode=fr<wait>",
    " console-setup/modelcode=pc105<wait>",
    " fb=false<wait>",
    "<f10>"
  ]
  boot_wait = "10s"
  
  http_directory = "http"
  #iso_url   = "https://ubuntu.mirrors.ovh.net/ubuntu-releases/24.04/${var.ubuntu_iso_file}"
  iso_url   = "../images/${var.ubuntu_iso_file}"
  iso_checksum = "file:https://ubuntu.mirrors.ovh.net/ubuntu-releases/24.04.4/SHA256SUMS"
  memory = 4096
  
  ssh_password = "opensvcpacker"
  ssh_username = "packer"
  ssh_timeout = "30m"
  ssh_port = 22
  shutdown_command = "echo 'opensvcpacker' | sudo -S shutdown -P now"

  headless = true
  accelerator = "kvm"
  format = "qcow2"
  disk_size = "20G"
  disk_interface = "virtio"
  net_device = "virtio-net"
  cpus = 4
  vnc_bind_address = "0.0.0.0"
  vnc_port_min = "22013"
  vnc_port_max = "22013"

  efi_boot = true
  efi_firmware_code = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  efi_firmware_vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"

  qemuargs = [
    ["-accel", "kvm"],
    ["-cpu", "host"],
    ["-machine", "pc-q35-6.2,usb=off,vmport=off,dump-guest-core=off"],
    ["-smp", "4,sockets=4,cores=1,threads=1"],
  ] 
  vm_name = "${var.vm_template_name}"
}

build {
  sources = [ "source.qemu.custom_image" ]
  provisioner "shell" {
    inline = [ "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 2; done" ]
  }
  provisioner "shell" {
    inline = [
      "cd /opt && sudo mkdir archives && sudo chmod 777 archives"
    ]
  }
  provisioner "file" {
    source = "${var.archives_directory}"
    destination = "/opt/archives"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "../common/git-clone-vmtools.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "./scripts/ansible.sh"
  }
  provisioner "breakpoint" {
    disable = true
    note    = "this is a breakpoint"
  }
  provisioner "ansible-local" {
    playbook_file = "../common/ansible/env.yml"
    galaxy_file = "../common/ansible/requirements.yml"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "../common/reboot.sh"
    expect_disconnect = "true"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    pause_before    = "1m0s"
    script          = "./scripts/zfs.sh"
  }
  provisioner "shell" {
    environment_vars = [
     "LINBIT_KEY=${var.LINBIT_KEY}"
    ]
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/linbit.apt.repo.sh"
  }
  provisioner "breakpoint" {
    disable = true
    note    = "this is a breakpoint"
  }
  provisioner "shell" {
    inline = [
      "cd /opt/vm-tools/build/common/ansible && sudo ./bootstrap.sh"
    ]
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/custom/custom.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/cleanup.sh"
  }
}
