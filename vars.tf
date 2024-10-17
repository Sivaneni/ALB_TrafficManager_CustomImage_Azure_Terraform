variable "client_id" {
  description = "The Client ID for the Service Principal"
  type        = string
}

variable "client_secret" {
  description = "The Client Secret for the Service Principal"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "The Tenant ID for the Service Principal"
  type        = string
}

variable "subscription_id" {
  description = "The Subscription ID for the Azure account"
  type        = string
}


variable "resource_group_name" {
  type    = string
  default = "tf-rg"

}
variable "Exisitng_resource_group_name" {
  type = string

}
variable "location" {
  type    = string
  default = "eastus"

}
variable "vnet_name" {
  type = string
}
variable "vnet_address_space" {
  type = list(any)
}
variable "web_subnet_name" {
  type = string
}
variable "subnet_address_space1" {
  type = list(any)

}

variable "app_subnet_name" {
  type = string
}
variable "subnet_address_space2" {
  type = list(any)

}


variable "DB_subnet_name" {
  type = string
}
variable "subnet_address_space3" {
  type = list(any)

}




