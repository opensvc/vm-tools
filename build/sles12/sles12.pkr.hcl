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
  default = "packer-uefi-sles12sp5.qcow2"
}

variable "sles12_iso_file" {
  type    = string
  default = "SLE-12-SP5-Server-DVD-x86_64-Boothole-Respin-DVD1.iso"
}

variable "suse_key" {
  type      = string
  default   = "undefined"
  sensitive = true
}

variable "suse_email" {
  type      = string
  default   = "undefined"
  sensitive = true
}

variable "LINBIT_KEY" {
  type      = string
  default   = "undefined"
  sensitive = true
}

source "qemu" "custom_image" {
  
  boot_command = [
    "e<wait>",
    "<down><down><down><down><wait>",
    "<end><wait>",
    " netdevice=eth0 netsetup=dhcp install=cd:/",
    " lang=en_US autoyast=http://{{ .HTTPIP }}:{{ .HTTPPort }}/sles12-autoinst.xml",
    " textmode=1",
    "<f10><wait>"
  ]
  boot_wait = "5s"
  #boot_wait = "10h"
  
  http_directory = "http"
  iso_url   = "file:///data/vdc/build/images/${var.sles12_iso_file}"
  iso_checksum = "a8096868c687fbd82766603958a678194f3ec9becb4c945d9d0a46544b4cd674"
  memory = 4096
  
  ssh_password = "opensvcpacker"
  ssh_username = "packer"
  ssh_timeout = "30m"
  ssh_port = 22
  shutdown_command = "echo 'opensvcpacker' | sudo -S shutdown -P now"

  headless = true
  accelerator = "kvm"
  format = "qcow2"
  disk_size = "40G"
  disk_interface = "virtio"
  disk_discard = "unmap"
  disk_detect_zeroes = "unmap"
  net_device = "virtio-net"
  cpus = 4
  vnc_bind_address = "0.0.0.0"
  vnc_port_min = "32014"
  vnc_port_max = "32014"

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
    environment_vars = [
      "SUSE_KEY=${var.suse_key}",
      "SUSE_EMAIL=${var.suse_email}"
    ]
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-register.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-snapper.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-update.sh"
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
  provisioner "breakpoint" {
    disable = true
    note    = "Troubleshooting Breakpoint"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "./scripts/install-cni.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-additional-pkg.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "../common/git-clone-vmtools.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "./scripts/ansible.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-cloud-init.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = "true"
    script          = "../common/reboot.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    pause_before    = "1m0s"
    script = "../common/sles-zfs.sh"
  }
  provisioner "shell" {
    environment_vars = [
      "LINBIT_KEY=${var.LINBIT_KEY}"
    ]
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/linbit.zypper.repo.sh"
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
    script = "../common/sles-unregister.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-cleanup.sh"
  }
}
