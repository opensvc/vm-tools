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
  default = "packer-uefi-sles16.qcow2"
}

variable "sles16_iso_file" {
  type    = string
  default = "SLES-16.0-Full-x86_64-GM.install.iso"
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
  
  # SLES 16 installs with Agama: boot the installer from the grub command line
  # (the default menu entry boots the hard disk) with an Agama json profile
  boot_command = [
    "c<wait>",
    "linux ($root)/boot/x86_64/loader/linux inst.auto=http://{{ .HTTPIP }}:{{ .HTTPPort }}/sles16.json security= selinux=0<enter><wait5>",
    "initrd ($root)/boot/x86_64/loader/initrd<enter><wait30>",
    "boot<enter>"
  ]
  boot_wait = "5s"
  
  http_directory = "http"
  iso_url   = "file:///data/vdc/build/images/${var.sles16_iso_file}"
  iso_checksum = "86dcdb8730622fab5d073a07610522bb10791a58f052eb304f88d653e1bb0d6a"
  memory = 4096
  
  ssh_password = "opensvcpacker"
  ssh_username = "packer"
  ssh_timeout = "45m"
  ssh_port = 22
  shutdown_command = "echo 'opensvcpacker' | sudo -S shutdown -P now"

  headless = true
  accelerator = "kvm"
  format = "qcow2"
  disk_size = "40G"
  disk_interface = "virtio"
  net_device = "virtio-net"
  cpus = 4
  vnc_bind_address = "0.0.0.0"
  vnc_port_min = "21516"
  vnc_port_max = "21516"

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
    script = "../common/sles16-additional-pkg.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "../common/git-clone-vmtools.sh"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script = "../common/sles-ansible.sh"
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
  provisioner "breakpoint" {
    disable = true
    note    = "Troubleshooting Breakpoint"
  }
  provisioner "shell" {
    execute_command = "echo 'opensvcpacker' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    pause_before    = "1m0s"
    script = "../common/sles16-zfs.sh"
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
