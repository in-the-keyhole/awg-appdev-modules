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

variable subnet {
  type = object({
    id = string
  })
}

variable replicas {
  type = number
}

variable dns_names {
  type = set(string)
}

variable stepca_token {
  type = string
}

variable stepca_uuid {
  type = string
}

variable admin_username {
  type = string
}

variable admin_password {
  type = string
}

terraform {
  required_providers {
    smallstep = {
      source = "smallstep/smallstep"
      version = "0.6.0"
    }
    jwk = {
      source = "tieto-cem/jwk",
      version = "1.1.0"
    }
  }
}

provider smallstep {
  bearer_token = var.stepca_token
}

data azurerm_client_config current {

}

data smallstep_authority ca {
  id = var.stepca_uuid
}

resource jwk_ec_key jwk {
  count = var.replicas

  use = "sig"  
  kid = "${var.name}-${count.index}"
  alg = "ES256"
  crv = "P-256"
}

resource smallstep_provisioner jwk {
  count = var.replicas

  authority_id = data.smallstep_authority.ca.id
  name = "${var.name}-${count.index}"
  type = "JWK"

  jwk = {
    key = "${nonsensitive(provider::jwk::public_key(jwk_ec_key.jwk[count.index].json, "encrypt-1"))}\n"
    encrypted_key = jwk_ec_key.jwk[count.index].json
  }
}

# create availability set to link stepca instances together
resource azurerm_availability_set stepca {
  name = "${var.name}-stepca"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location
  
  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

resource azurerm_network_security_group stepca {
  name = "${var.name}-stepca"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  security_rule {
    name = "HTTPS"
    priority = 1001
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "443"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  
  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

resource azurerm_network_interface stepca {
  count = var.replicas
  
  name = "${var.name}-stepca-${count.index}"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location
  internal_dns_name_label = "${var.name}-stepca-${count.index}"
  
  ip_configuration {
    name = "ipconfig0"
    subnet_id = var.subnet.id
    private_ip_address_allocation = "Dynamic"
  }


  lifecycle {
    ignore_changes = [tags]
  }
}

resource azurerm_network_interface_security_group_association stepca {
  count = var.replicas
  network_interface_id = azurerm_network_interface.stepca[count.index].id
  network_security_group_id = azurerm_network_security_group.stepca.id
}

data template_file stepca_execute {
  count = var.replicas

  template = replace(<<-EOF
#!/bin/bash -e

# download install script
curl -sSLO https://files.smallstep.com/install-step-ra.sh

# execute install script
bash install-step-ra.sh \
  --ca-url "https://${data.smallstep_authority.ca.domain}/" \
  --fingerprint "${data.smallstep_authority.ca.fingerprint}" \
  --provisioner-name "${var.name}-stepca-${count.index}" \
  --provisioner-password-file "/run/provisioner.passwd" \
  --dns-names "${join(",", var.dns_names)}" \
  --listen-address ":443"
  
# output service status
systemctl daemon-reload
systemctl enable step-ca
systemctl start  step-ca
systemctl status step-ca
journalctl -u step-ca
EOF
  , "\r\n", "\n")
}

data template_cloudinit_config stepca {
  count = var.replicas

  gzip = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = replace(<<-EOF
      #cloud-config
      packages:
      - apt-utils
      - curl
      - jq
      write_files:
      - path: /run/provisioner.passwd
        encoding: b64
        content: ${base64encode("")}
        owner: 'root:root'
      - path: /run/execute.sh
        encoding: b64
        content: ${base64encode(data.template_file.stepca_execute[count.index].rendered)}
        owner: 'root:root'
        permissions: 0755
      runcmd:
      - apt-get update
      - apt-get install -y curl jq
      - /run/execute.sh
      EOF
      , "\r\n", "\n")
  }
}

resource azurerm_linux_virtual_machine stepca {
  count = var.replicas

  name = "${var.name}-stepca-${count.index}"
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  size = "Standard_B1s"
  availability_set_id = azurerm_availability_set.stepca.id
  network_interface_ids = [azurerm_network_interface.stepca[count.index].id]
  disable_password_authentication = false
  secure_boot_enabled = true
  custom_data = data.template_cloudinit_config.stepca[count.index].rendered
  
  computer_name  = "${var.name}-stepca-${count.index}"
  admin_username = var.admin_username
  admin_password = var.admin_password

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name = "${var.name}-stepca-${count.index}-osdisk"
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

# resource azurerm_virtual_machine_extension stepca {
#   count = var.replicas

#   name = "AADSSHLogin"
#   tags = var.tags
#   virtual_machine_id = azurerm_linux_virtual_machine.stepca[count.index].id
#   publisher = "Microsoft.Azure.ActiveDirectory"
#   type = "AADSSHLoginForLinux"
#   type_handler_version = "1.0"
#   auto_upgrade_minor_version = true
# }

# resource azurerm_role_assignment stepca_aad_vm_admin_login {
#   count = var.replicas
#   role_definition_name = "Virtual Machine Administrator Login"
#   scope = azurerm_linux_virtual_machine.stepca[count.index].id
#   principal_id = data.azurerm_client_config.current.object_id
# }
