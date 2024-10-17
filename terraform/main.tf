

# Configure the Microsoft Azure Provider

#provides authentication and authorization by adding service principle to iam roles of subscription with owner access
provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

}
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



resource "azurerm_resource_group" "kube-rg" {
  name     = "centralus-rg"
  location = "eastus"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-1"
  location            = azurerm_resource_group.kube-rg.location
  resource_group_name = azurerm_resource_group.kube-rg.name
  address_space       = ["10.0.0.0/16"]
  subnet {
    name             = "subnet1"
    address_prefixes = ["10.0.1.0/24"]

  }
}

data "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.kube-rg.name
}

output "subnet2_id" {
  value = data.azurerm_subnet.subnet1.id
}
resource "azurerm_network_interface" "nic" {
  name                = "nic"
  location            = azurerm_resource_group.kube-rg.location
  resource_group_name = azurerm_resource_group.kube-rg.name

  ip_configuration {
    name = "vm_ipconfig"
    #already exsitng subnet with nsg attached
    subnet_id                     = data.azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_network_security_group" "NSG" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.kube-rg.location
  resource_group_name = azurerm_resource_group.kube-rg.name

  security_rule {
    name                       = "HTTPALLOW"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


}
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_assoc" {
  subnet_id                 = data.azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.NSG.id
}


resource "azurerm_public_ip" "pip" {
  name                = "pip"
  location            = azurerm_resource_group.kube-rg.location
  resource_group_name = azurerm_resource_group.kube-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}




resource "azurerm_linux_virtual_machine" "Terraformvm" {
  name                  = "vm"
  location              = azurerm_resource_group.kube-rg.location
  resource_group_name   = azurerm_resource_group.kube-rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                  = "Standard_DS1_v2"
  admin_username        = "adminuser"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("${path.module}/id_rsa.pub")
  }


  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y nginx",
      "public_ip=$(curl api.ipify.org)",
      "region=$(curl -H Metadata:true 'http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text')",
      "echo \"Public IP: $public_ip\"",
      "echo \"Region: $region\"",
      "echo \"<html><body><h1>Public IP: $public_ip</h1><h2>Region: $region</h2></body></html>\" > /tmp/index.html",
      "sudo mv /tmp/index.html /var/www/html/index.nginx-debian.html"
    ]
  }
  connection {
    type        = "ssh"
    user        = "adminuser"
    private_key = file("${path.module}/id_rsa")
    host        = azurerm_public_ip.pip.ip_address
  }
}


