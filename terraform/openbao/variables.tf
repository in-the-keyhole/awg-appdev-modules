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

variable tls_keyvault_secret {
  type = object({
    id = string
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