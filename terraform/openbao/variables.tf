variable name {
  type = string
}

variable tags {
  type = map(string)
  default = {}
}

variable resource_group {
  type = object({
    id = string
    name = string
    location = string
  })
}

variable location {
  type = string
}

variable identity {
  type = object({
    id = string
    principal_id = string
    client_id = string
  })
}

variable zones {
  type = list(number)
}

variable vm_sku {
  type = string
}

variable vnet {
  type = object({
    id = string
    name = string
  })
}

variable subnet {
  type = object({
    id = string
  })
}

variable admin_username {
  type = string
}

variable admin_password {
  type = string
}

variable instance_count {
  type = number
}

variable root_ca_certs {
  type = string
}

variable keyvault {
  type = object({
    id = string
    name = string
  })
}

variable keyvault_key {
  type = object({
    id = string
    name = string
  })
}

variable tls_keyvault_certificate {
  type = object({
    id = string
    name = string
    secret_id = string
    version = string
    versionless_id = string
    versionless_secret_id = string
    thumbprint = string
    resource_manager_id = string
    resource_manager_versionless_id = string
  })
}

variable load_balancer {
  type = object({
    id = string
    name = string
  })
}

variable load_balancer_front_end {
  type = object({
    name = string
  })
}

variable dns_name {
  type = string
}