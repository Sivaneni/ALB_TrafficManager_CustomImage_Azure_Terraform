#provides authentication and authorization by adding service principle to iam roles of subscription with owner access
provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}



resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}





resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space

}



# Define the subnet and NSG separately
resource "azurerm_subnet" "subnets" {
  # count                = 3
  # name                 = element(["web-subnet", "app-subnet", "db-subnet"], count.index)
  name                 = "snet-01"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_address_space1
  depends_on           = [azurerm_virtual_network.vnet]
}

resource "azurerm_network_security_group" "nsgs" {
  # count               = 3
  # name                = element(["web-nsg", "app-nsg", "db-nsg"], count.index)
  name                = "nsg-01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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
  depends_on = [azurerm_subnet.subnets]
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  # count                     = 3
  subnet_id                 = azurerm_subnet.subnets.id
  network_security_group_id = azurerm_network_security_group.nsgs.id
  depends_on                = [azurerm_network_security_group.nsgs]
}

# Create public IPs for each VM
#he format("VM-%02d-pip", count.index + 1) part will replace %02d with a zero-padded two-digit number, starting from 01, 02, and so on
resource "azurerm_public_ip" "pip" {
  count               = 3
  name                = format("VM-%02d-pip", count.index + 1)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [azurerm_subnet_network_security_group_association.nsg_association]
}

# Create network interfaces for each VM
resource "azurerm_network_interface" "nic" {
  count               = 3
  name                = format("VM-%02d-nic", count.index + 1)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = format("VM-%02d-ipconfig", count.index + 1)
    subnet_id                     = azurerm_subnet.subnets.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[count.index].id
  }

  depends_on = [
    azurerm_public_ip.pip
  ]
}

output "network_interface_details" {
  value = azurerm_network_interface.nic
}



# Create virtual machines for each subnet
resource "azurerm_linux_virtual_machine" "vm" {
  count                           = 3
  name                            = format("VM-%02d", count.index + 1)
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  network_interface_ids           = [azurerm_network_interface.nic[count.index].id]
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"
  disable_password_authentication = true


  admin_ssh_key {
    username   = "adminuser"
    public_key = file("${path.module}/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_id = "/subscriptions/ee7895f1-8afc-49c0-91cf-cf21219d8fdb/resourceGroups/kube-rg/providers/Microsoft.Compute/images/ngniximg1310"
  provisioner "remote-exec" {
    inline = [
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
    host        = azurerm_public_ip.pip[count.index].ip_address
  }
  depends_on = [azurerm_network_interface.nic]

}




//Below 2 resources are for create a public ip and assocaite to load balancer


resource "azurerm_public_ip" "PublicIPForLB" {
  name                = "PublicIPForLB"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  depends_on          = [azurerm_linux_virtual_machine.vm]
}

resource "azurerm_lb" "VMLoadBalancer" {
  name                = "VMLoadBalancer"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.PublicIPForLB.id
  }
  depends_on = [azurerm_public_ip.PublicIPForLB]
}


resource "azurerm_lb_backend_address_pool" "BackEndAddressPool" {
  loadbalancer_id = azurerm_lb.VMLoadBalancer.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_backend_address_pool_address" "BackEndAddress" {
  count                   = 3
  name                    = format("BackEndAddress-%02d", count.index)
  backend_address_pool_id = azurerm_lb_backend_address_pool.BackEndAddressPool.id
  ip_address              = azurerm_network_interface.nic[count.index].private_ip_address
  virtual_network_id      = azurerm_virtual_network.vnet.id

  depends_on = [azurerm_lb_backend_address_pool.BackEndAddressPool]
}

#An "azurerm_lb_nat_rule" is not strictly required unless you need specific inbound NAT rules for forwarding traffic from the load balancer’s frontend to backend VMs. If your setup doesn’t need such specific traffic forwarding, you can skip it

#  "azurerm_lb_outbound_rule" is for routing outbound traffic through a specific IP. If you already have a Network Security Group (NSG) for your VMs, an outbound rule for the load balancer might be redundant if your primary concern is security. NSGs can handle both inbound and outbound traffic rules, controlling access effectively.The azurerm_lb_outbound_rule is more about routing outbound traffic through a specific IP, which can be useful for tracking, billing, and compliance purposes. But if your setup is more straightforward and the NSG is doing the job, you might not need it.

resource "azurerm_lb_probe" "lbprobe" {
  loadbalancer_id     = azurerm_lb.VMLoadBalancer.id
  name                = "http_probe"
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}
/*
The "azurerm_lb_rule" resource defines a load balancing rule in Azure. It specifies how incoming traffic on the frontend IP is distributed to the backend pool. Here’s what each piece does:
    resource_group_name: Which resource group the rule belongs to.
    loadbalancer_id: ID of the load balancer.
    name: Name of the rule.

    protocol: Protocol to balance (TCP, UDP).

    frontend_port: Port on the frontend IP to balance.

    backend_port: Port on the backend pool to balance.

    frontend_ip_configuration: Which frontend IP configuration to use.

    backend_address_pool: Which backend pool to use.
*/
resource "azurerm_lb_rule" "example" {
  loadbalancer_id                = azurerm_lb.VMLoadBalancer.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.lbprobe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.BackEndAddressPool.id]
}



