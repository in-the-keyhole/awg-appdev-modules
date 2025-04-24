variable name {
  type = string
}

variable tags {
  type = map(string)
}

variable resource_group {
  type = object({
    name = string
  })
}

variable location {
  type = string
}

variable admin_username {
  type = string
}

variable admin_password {
  type = string
}

variable subnet {
  type = object({
    id = string
  })
}

variable addresses {
  type = list(string)
}

variable rules {
  type = map(list(string))
  default = {
    "." = [ "168.63.129.16" ]
  }
}

data azurerm_client_config current {

}

# create NSG for interfaces
resource azurerm_network_security_group dns_resolver {
  name = "${var.name}-dns-resolver"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  security_rule {
    name = "DNS"
    priority = 1001
    direction = "Inbound"
    access = "Allow"
    protocol = "Udp"
    source_port_range = "*"
    destination_port_range = "53"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  
  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

# create availability set to link resolvers together
resource azurerm_availability_set dns_resolver {
  name = "${var.name}-dns-resolver"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location
  
  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

resource azurerm_network_interface dns_resolver {
  count = length(var.addresses)
  
  name = "${var.name}-dns-resolver-${count.index}"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location
  
  dns_servers = [ "168.63.129.16" ]

  ip_configuration {
    name = "ipconfig0"
    subnet_id = var.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address = var.addresses[count.index]
  }


  lifecycle {
    ignore_changes = [tags]
  }
}

resource azurerm_network_interface_security_group_association dns_resolver {
  count = length(var.addresses)
  network_interface_id = azurerm_network_interface.dns_resolver[count.index].id
  network_security_group_id = azurerm_network_security_group.dns_resolver.id
}

data template_file dns_resolver_service {
  template = replace(<<-EOF
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile

[Install]
WantedBy=multi-user.target
EOF
, "\r\n", "\n")
}

data template_file dns_resolver_execute {
  template = replace(<<-EOF
    #!/bin/bash -e

    cd /tmp
    cat /etc/coredns/Corefile
    wget https://github.com/coredns/coredns/releases/download/v1.12.1/coredns_1.12.1_linux_amd64.tgz
    tar xvf coredns_1.12.1_linux_amd64.tgz
    rm coredns_1.12.1_linux_amd64.tgz
    mv coredns /usr/local/bin/
    systemctl daemon-reload
    systemctl start coredns
    systemctl status coredns
    EOF
    , "\r\n", "\n")
}

data template_cloudinit_config dns_resolver {
  gzip = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = replace(<<-EOF
      #cloud-config
      packages:
      - apt-utils
      - wget
      write_files:
      - path: /etc/coredns/Corefile
        encoding: b64
        content: ${base64encode(replace(templatefile("${path.module}/Corefile.tftpl", { rules = var.rules }), "\r\n", "\n"))}
        owner: 'root:root'
        permissions: 0644
      - path: /etc/systemd/system/coredns.service
        encoding: b64
        content: ${base64encode(data.template_file.dns_resolver_service.rendered)}
        owner: 'root:root'
        permissions: 0644
      - path: /run/execute.sh
        encoding: b64
        content: ${base64encode(data.template_file.dns_resolver_execute.rendered)}
        owner: 'root:root'
        permissions: 0755
      runcmd:
      - apt-get update
      - apt-get install -y wget
      - /run/execute.sh
      EOF
      , "\r\n", "\n")
  }
}

resource azurerm_linux_virtual_machine dns_resolver {
  count = length(var.addresses)

  name = "${var.name}-dns-resolver-${count.index}"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  size = "Standard_B1s"
  availability_set_id = azurerm_availability_set.dns_resolver.id
  network_interface_ids = [azurerm_network_interface.dns_resolver[count.index].id]
  disable_password_authentication = false
  secure_boot_enabled = true
  custom_data = data.template_cloudinit_config.dns_resolver.rendered
  
  computer_name  = "${var.name}-dns-resolver-${count.index}"
  admin_username = var.admin_username
  admin_password = var.admin_password

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name = "${var.name}-dns-resolver-${count.index}-osdisk"
    disk_size_gb = 30
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "ubuntu-24_10"
    sku = "minimal"
    version = "latest"
  }
  
  boot_diagnostics {
    
  }

  lifecycle {
    ignore_changes = [tags, identity]
  }
}

# resource azurerm_virtual_machine_extension dns_resolver {
#   count = length(var.addresses)

#   name = "AADSSHLogin"
#   tags = var.tags
#   virtual_machine_id = azurerm_linux_virtual_machine.dns_resolver[count.index].id
#   publisher = "Microsoft.Azure.ActiveDirectory"
#   type = "AADSSHLoginForLinux"
#   type_handler_version = "1.0"
#   auto_upgrade_minor_version = true
# }

# resource azurerm_role_assignment dns_resolver_aad_vm_admin_login {
#   count = length(var.addresses)
#   role_definition_name = "Virtual Machine Administrator Login"
#   scope = azurerm_linux_virtual_machine.dns_resolver[count.index].id
#   principal_id = data.azurerm_client_config.current.object_id
# }
