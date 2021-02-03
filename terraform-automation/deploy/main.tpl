provider azurerm {
  client_id = "{{ client_id }}"
  subscription_id = "{{ subscription_id }}"
  tenant_id = "{{ tenant_id }}"
  client_secret = "{{ client_secret }}"
  features {}
}

#
# Create a random id
#
resource random_id id {
  byte_length = 2
}

locals {
  # Ids for multiple sets of EC2 instances, merged together
  hostname    = format("bigip.azure.%s.com", local.student_id)
}

#
# Create a resource group
#
resource azurerm_resource_group rg {
  name     = format("student-%s-%s-rg", local.student_id, random_id.id.hex)
  location = var.location
}

resource "azurerm_public_ip" "alb_public_ip" {
  name                = format("%s-alb-pip", local.student_id)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones             = var.availabilityZones
}

#
# Create a load balancer for bigip(s)
#
resource "azurerm_lb" "alb" {
  name                = format("%s-alb-bigip", local.student_id)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.alb_public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "alb-backend" {
  resource_group_name = azurerm_resource_group.rg.name
  loadbalancer_id     = azurerm_lb.alb.id
  name                = format("f5pool-%s%", local.student_id)
}

#
#Create N-nic bigip
#
module bigip {
  count 		     = local.instance_count
  source                     = "../"
  prefix                     = format("%s-2nic", var.prefix)
  resource_group_name        = azurerm_resource_group.rg.name
  mgmt_subnet_ids            = [{ "subnet_id" = data.azurerm_subnet.mgmt.id, "public_ip" = true, "private_ip_primary" =  ""}]
  mgmt_securitygroup_ids     = [module.mgmt-network-security-group.network_security_group_id]
  external_subnet_ids        = [{ "subnet_id" = data.azurerm_subnet.external-public.id, "public_ip" = true,"private_ip_primary" = "", "private_ip_secondary" = ""}]
  external_securitygroup_ids = [module.external-network-security-group-public.network_security_group_id]
  availabilityZones          = var.availabilityZones
}


resource "null_resource" "clusterDO" {

  count = local.instance_count

  provisioner "local-exec" {
    command = "cat > DO_2nic-instance${count.index}.json <<EOL\n ${module.bigip[count.index].onboard_do}\nEOL"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf DO_2nic-instance${count.index}.json"
  }
  depends_on = [ module.bigip.onboard_do]
}


#
# Create the Network Module to associate with BIGIP
#

module "network" {
  source              = "Azure/vnet/azurerm"
  vnet_name           = format("%s-vnet-%s", local.student_id, random_id.id.hex)
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.cidr]
  subnet_prefixes     = [cidrsubnet(var.cidr, 8, 1), cidrsubnet(var.cidr, 8, 2)]
  subnet_names        = ["mgmt-subnet", "external-public-subnet"]

  tags = {
    environment = "dev"
    costcenter  = "it"
  }
}

data "azurerm_subnet" "mgmt" {
  name                 = "mgmt-subnet"
  virtual_network_name = module.network.vnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  depends_on           = [module.network]
}

data "azurerm_subnet" "external-public" {
  name                 = "external-public-subnet"
  virtual_network_name = module.network.vnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  depends_on           = [module.network]
}

#
# Create the Network Security group Module to associate with BIGIP-Mgmt-Nic
#
module mgmt-network-security-group {
  source              = "Azure/network-security-group/azurerm"
  resource_group_name = azurerm_resource_group.rg.name
  security_group_name = format("%s-mgmt-nsg-%s", local.student_id, random_id.id.hex )
  tags = {
    environment = "dev"
    costcenter  = "terraform"
  }
}

#
# Create the Network Security group Module to associate with BIGIP-External-Nic
#
module external-network-security-group-public {
  source              = "Azure/network-security-group/azurerm"
  resource_group_name = azurerm_resource_group.rg.name
  security_group_name = format("%s-external-public-nsg-%s", local.student_id, random_id.id.hex)
  tags = {
    environment = "dev"
    costcenter  = "terraform"
  }
}

resource "azurerm_network_security_rule" "mgmt_allow_https" {
  name                        = "Allow_Https"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  destination_address_prefix  = "*"
  source_address_prefixes     = var.AllowedIPs
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = format("%s-mgmt-nsg-%s", local.student_id, random_id.id.hex)
  depends_on                  = [module.mgmt-network-security-group]
}
resource "azurerm_network_security_rule" "mgmt_allow_ssh" {
  name                        = "Allow_ssh"
  priority                    = 202
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  destination_address_prefix  = "*"
  source_address_prefixes     = var.AllowedIPs
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = format("%s-mgmt-nsg-%s", local.student_id, random_id.id.hex)
  depends_on                  = [module.mgmt-network-security-group]
}

resource "azurerm_network_security_rule" "external_allow_https" {
  name                        = "Allow_Https"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  destination_address_prefix  = "*"
  source_address_prefixes     = var.AllowedIPs
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = format("%s-external-public-nsg-%s", local.student_id, random_id.id.hex)
  depends_on                  = [module.external-network-security-group-public]
}
resource "azurerm_network_security_rule" "external_allow_ssh" {
  name                        = "Allow_ssh"
  priority                    = 202
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  destination_address_prefix  = "*"
  source_address_prefixes     = var.AllowedIPs
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = format("%s-external-public-nsg-%s", local.student_id, random_id.id.hex)
  depends_on                  = [module.external-network-security-group-public]
}






