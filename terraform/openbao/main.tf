terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~>2.3"
    }
  }
}

data azurerm_client_config current {

}

locals {
  install_openbao_sh = replace(templatefile("${path.module}/templates/install_openbao.sh.tpl", {
    tenant_id = data.azurerm_client_config.current.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id
    client_id = var.identity.client_id
    resource_group = var.resource_group
    vm_scale_set_name = var.name
    keyvault = var.keyvault
    keyvault_key = var.keyvault_key
    tls_keyvault_certificate = var.tls_keyvault_certificate
    leader_tls_servername = var.dns_name
  }), "\r\n", "\n")
}

output "keyv" {
  value = var.tls_keyvault_certificate
}

data template_cloudinit_config openbao {
  gzip = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = replace(<<-EOF
      #cloud-config
      packages:
      - apt-utils
      - ca-certificates
      - curl
      write_files:
      - path: /usr/local/share/ca-certificates/awg.crt
        owner: "root:root"
        permissions: "0644"
        encoding: b64
        content: ${base64encode(var.root_ca_certs)}
      - path: /etc/cron.hourly/install_openbao_tls.sh
        owner: "root:root"
        permissions: "0755"
        content: |
          #!/bin/bash -e

          # wait for AKV certificate
          while [ ! -f /var/lib/waagent/Microsoft.Azure.KeyVault.Store/${var.keyvault.name}.${var.tls_keyvault_certificate.name} ]; do
            sleep 5
          done
          
          openssl ec -outform pem -in /var/lib/waagent/Microsoft.Azure.KeyVault.Store/${var.keyvault.name}.${var.tls_keyvault_certificate.name} -out /opt/openbao/tls/tls.key
          openssl x509 -outform pem -in /var/lib/waagent/Microsoft.Azure.KeyVault.Store/${var.keyvault.name}.${var.tls_keyvault_certificate.name} -out /opt/openbao/tls/tls.crt

          systemctl reload openbao

      - path: /usr/local/bin/install_openbao.sh
        encoding: b64
        content: ${base64encode(local.install_openbao_sh)}
        owner: "root:root"
        permissions: "0755"
      runcmd:
      - apt-get update
      - update-ca-certificates
      - update-ca-certificates
      - /usr/local/bin/install_openbao.sh
      - /etc/cron.hourly/install_openbao_tls.sh
      EOF
      , "\r\n", "\n")
  }
}

resource azapi_resource ssh_public_key {
  type = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name = var.name
  tags = var.tags
  location  = var.location
  parent_id = var.resource_group.id

  lifecycle {
    ignore_changes = [ tags ]
  }
}

resource azapi_resource_action ssh_public_key {
  type = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action = "generateKeyPair"
  method = "POST"
  response_export_values = ["publicKey", "privateKey"]
}

resource azurerm_lb_backend_address_pool openbao {
  name = var.name
  loadbalancer_id = var.load_balancer.id
}

resource azurerm_lb_rule openbao {
  name = var.name
  loadbalancer_id = var.load_balancer.id
  protocol = "Tcp"
  frontend_port = 443
  backend_port = 8200
  disable_outbound_snat = true
  frontend_ip_configuration_name = var.load_balancer_front_end.name
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.openbao.id]
  probe_id = azurerm_lb_probe.openbao.id
}

resource azurerm_lb_probe openbao {
  name = var.name
  loadbalancer_id = var.load_balancer.id
  protocol = "Https"
  port = 8200
  request_path = "/v1/sys/health?standbyok=true"
}

resource azurerm_network_security_group openbao {
  name = var.name
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  security_rule {
    name = "Api"
    priority = 1002
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "8200"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "Cluster"
    priority = 1003
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "8201"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  
  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

resource azurerm_linux_virtual_machine_scale_set openbao {
  name = var.name
  tags = var.tags
  resource_group_name = var.resource_group.name
  location = var.location

  upgrade_mode = "Automatic"
  instances = var.instance_count
  sku = var.vm_sku
  zones = var.zones
  computer_name_prefix = "${var.name}-"
  disable_password_authentication = false
  admin_username = var.admin_username
  admin_password = var.admin_password
  custom_data = data.template_cloudinit_config.openbao.rendered
  health_probe_id = azurerm_lb_probe.openbao.id

  rolling_upgrade_policy {
    max_batch_instance_percent = 20
    max_unhealthy_instance_percent = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches = "PT10M"
    prioritize_unhealthy_instances_enabled = true
  }

  # automatic_instance_repair {
  #   enabled = true
  #   action = "Reimage"
  #   grace_period = "PT10M"
  # }

  admin_ssh_key  {
    username = var.admin_username
    public_key = azapi_resource_action.ssh_public_key.output.publicKey
  }

  network_interface {
    name = var.name
    primary = true
    network_security_group_id = azurerm_network_security_group.openbao.id
    
    ip_configuration {
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.openbao.id]
      name = "ipconfig0"
      primary = true
      subnet_id = var.subnet.id
    }
  }

  identity {
    identity_ids = [var.identity.id]
    type = "UserAssigned"
  }

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "ubuntu-24_04-lts"
    sku = "server"
    version = "latest"
  }
  
  boot_diagnostics {
    
  }

  # extension {
  #   name = "HealthExtension"
  #   publisher = "Microsoft.ManagedServices"
  #   type = "ApplicationHealthLinux"
  #   type_handler_version = "2.0"
  #   automatic_upgrade_enabled = true
  #   auto_upgrade_minor_version = true

  #   settings = jsonencode({
  #     protocol = "https"
  #     port = 8200
  #     requestPath = "/v1/sys/health?standbyok=true"
  #     intervalInSeconds = 5
  #     numberOfProbes = 3
  #   })
  # }

  extension {
    name = "KeyVaultForLinux"
    publisher = "Microsoft.Azure.KeyVault"
    type = "KeyVaultForLinux"
    type_handler_version = "3.0"
    automatic_upgrade_enabled = true
    auto_upgrade_minor_version = true

    settings = jsonencode({
      secretsManagementSettings = {
        requireInitialSync = true
        observedCertificates = [{
          url = "${var.tls_keyvault_certificate.versionless_secret_id}"
        }]
      }
      authenticationSettings = {
          msiEndpoint = "http://169.254.169.254/metadata/identity"
          msiClientId = var.identity.client_id
      }
    })
  }

  lifecycle {
    ignore_changes = [ tags ]
    create_before_destroy = true
  }
}

resource azurerm_role_assignment openbao_reader {
  role_definition_name = "Reader"
  scope = azurerm_linux_virtual_machine_scale_set.openbao.id
  principal_id = var.identity.principal_id
}
