provider azurerm {
    features {}
}

provider "consul" {
  address = "3.95.15.85:8500"
}


#
# Create a random id
#
resource random_id id {
  byte_length = 2
}

locals {
  # Ids for multiple sets of EC2 instances, merged together
  hostname          = format("bigip.azure.%s.com", local.student_id)
  event_timestamp   = formatdate("YYYY-MM-DD hh:mm:ss",timestamp())
}

#
# Create a resource group
#
resource azurerm_resource_group rg {
  name     = format("student-%s-%s-rg", local.student_id, random_id.id.hex)
  location = var.location
}

#
# Create a load balancer resources for bigip(s) via azurecli
#
resource "azurerm_public_ip" "alb_public_ip" {
  name                = format("%s-alb-pip", local.student_id)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

data "template_file" "azure_cli_sh" {
  template = file("../../configs/azure_lb.sh")
  depends_on = [azurerm_resource_group.rg, azurerm_public_ip.alb_public_ip]
  vars = {
    rg_name         = azurerm_resource_group.rg.name
    public_ip       = azurerm_public_ip.alb_public_ip.name
    lb_name         = format("%s-loadbalancer", local.student_id)         
  }
}

resource "null_resource" "azure-cli" {
  
  provisioner "local-exec" {
    # Call Azure CLI Script here
    command = data.template_file.azure_cli_sh.rendered
  }
}

#
#Create N-nic bigip
#
module bigip {
  count 		     = var.bigip_count
  source                     = "../f5module/"
  prefix                     = format("%s-1nic", var.prefix)
  resource_group_name        = azurerm_resource_group.rg.name
  mgmt_subnet_ids            = [{ "subnet_id" = data.azurerm_subnet.mgmt.id, "public_ip" = true, "private_ip_primary" =  ""}]
  mgmt_securitygroup_ids     = [module.mgmt-network-security-group.network_security_group_id]
  availabilityZones          = var.availabilityZones
  app_name                   = var.app_name 
  law_id                     = azurerm_log_analytics_workspace.law.workspace_id
  law_primarykey             = azurerm_log_analytics_workspace.law.primary_shared_key

  providers = {
    consul = consul
  }

  depends_on                 = [null_resource.azure-cli]
}


resource "null_resource" "clusterDO" {

  count = var.bigip_count

  provisioner "local-exec" {
    command = "cat > DO_1nic-instance${count.index}.json <<EOL\n ${module.bigip[count.index].onboard_do}\nEOL"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf DO_1nic-instance${count.index}.json"
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
  subnet_prefixes     = [cidrsubnet(var.cidr, 8, 1)]
  subnet_names        = ["mgmt-subnet"]

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
# Create the Network Security group Module to associate with BIGIP-Mgmt-Nic
#

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
resource "azurerm_network_security_rule" "mgmt_allow_https2" {
  name                        = "Allow_Https_8443"
  priority                    = 201
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  destination_address_prefix  = "*"
  source_address_prefixes     = var.AllowedIPs
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = format("%s-mgmt-nsg-%s", local.student_id, random_id.id.hex)
  depends_on                  = [module.mgmt-network-security-group]
}

#
# Create backend application workloads
#
resource "azurerm_network_interface" "appnic" {
 count               = var.app_count
 name                = "app_nic_${count.index}"
 location            = azurerm_resource_group.rg.location
 resource_group_name = azurerm_resource_group.rg.name

 ip_configuration {
   name                          = "testConfiguration"
   subnet_id                     = data.azurerm_subnet.mgmt.id
   private_ip_address_allocation = "dynamic"
 }
}

resource "azurerm_managed_disk" "appdisk" {
 count                = var.app_count
 name                 = "datadisk_existing_${count.index}"
 location             = azurerm_resource_group.rg.location
 resource_group_name  = azurerm_resource_group.rg.name
 storage_account_type = "Standard_LRS"
 create_option        = "Empty"
 disk_size_gb         = "1023"
}

resource "azurerm_availability_set" "avset" {
 name                         = "avset"
 location                     = azurerm_resource_group.rg.location
 resource_group_name          = azurerm_resource_group.rg.name
 platform_fault_domain_count  = 2
 platform_update_domain_count = 2
 managed                      = true
}

resource "azurerm_virtual_machine" "app" {
 count                 = var.app_count
 name                  = "app_vm_${count.index}"
 location              = azurerm_resource_group.rg.location
 availability_set_id   = azurerm_availability_set.avset.id
 resource_group_name   = azurerm_resource_group.rg.name
 network_interface_ids = [element(azurerm_network_interface.appnic.*.id, count.index)]
 vm_size               = "Standard_DS1_v2"


 # Uncomment this line to delete the OS disk automatically when deleting the VM
 delete_os_disk_on_termination = true

 # Uncomment this line to delete the data disks automatically when deleting the VM
 delete_data_disks_on_termination = true

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "myosdisk${count.index}"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

 # Optional data disks
 storage_data_disk {
   name              = "datadisk_new_${count.index}"
   managed_disk_type = "Standard_LRS"
   create_option     = "Empty"
   lun               = 0
   disk_size_gb      = "1023"
 }

 storage_data_disk {
   name            = element(azurerm_managed_disk.appdisk.*.name, count.index)
   managed_disk_id = element(azurerm_managed_disk.appdisk.*.id, count.index)
   create_option   = "Attach"
   lun             = 1
   disk_size_gb    = element(azurerm_managed_disk.appdisk.*.disk_size_gb, count.index)
 }

 os_profile {
   computer_name  = format("appserver-%s", count.index)
   admin_username = "appuser"
   admin_password = var.upassword
   custom_data    = filebase64("../../configs/backend.sh")
 }

 os_profile_linux_config {
   disable_password_authentication = false
 }

  tags = {
    Name                = "${var.environment}-backendapp_${count.index}"
    environment         = var.environment
    owner               = var.owner
    group               = var.group
    costcenter          = var.costcenter
    application         = var.application
    tag_name            = "Env"
    value               = "consul"
    propagate_at_launch = true
    key                 = "Env"
    value               = "consul"
  }
}

#
# Create consul server
#
 resource "azurerm_public_ip" "mgmt_public_ip" {
  name                = "pip-mgmt-consul"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"   # Static is required due to the use of the Standard sku
  tags = {
    Name   = "pip-mgmt-consul"
    source = "terraform"
  }
}

resource "azurerm_network_interface" "consulvm-ext-nic" {
  name               = "${local.student_id}-consulvm-ext-nic"
  location           = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "primary"
    subnet_id                     =  data.azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.100"
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.mgmt_public_ip.id
  }

  tags = {
    Name        = "${local.student_id}-consulvm-ext-int"
    application = "consulserver"
    tag_name    = "Env"
    value       = "consul"
  }
}

resource "azurerm_virtual_machine" "consulvm" {
  name                  = "consulvm"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.consulvm-ext-nic.id]
  vm_size               = "Standard_DS1_v2"
  
  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true
  
  storage_os_disk {
    name              = "consulvmOsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "consulvm"
    admin_username = "consuluser"
    admin_password = var.upassword
    custom_data    = file("../../configs/consul.sh")

  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    Name                = "${local.student_id}-consulvm"
    tag_name            = "Env"
    value               = "consul"
    propagate_at_launch = true
  }
}

#
# Update central consul server
#
resource "consul_keys" "app" {
  datacenter = "dc1"
  # Set the CNAME of our load balancer as a key
  key {
    path  = format("adpm/labs/agility/students/%s/scaling/bigip/current_count", local.student_id)
    value = var.bigip_count
  }
  key {
    path  = format("adpm/labs/agility/students/%s/scaling/apps/%s/current_count", local.student_id, var.app_name)
    value = var.app_count
  }
  key {
    path  = format("adpm/labs/agility/students/%s/create_timestamp", local.student_id)
    value = local.event_timestamp
  }
  key {
    path  = format("adpm/labs/agility/students/%s/scaling/bigip/last_modified_timestamp", local.student_id)
    value = local.event_timestamp
  }
  key {
    path  = format("adpm/labs/agility/students/%s/scaling/apps/%s/last_modified_timestamp", local.student_id, var.app_name)
    value = local.event_timestamp
  }
  key {
    path  = format("adpm/labs/agility/students/%s/scaling/is_running", local.student_id)
    value = "false"
  } 
  key {
    path  = format("adpm/labs/agility/students/%s/consul_vip", local.student_id)
    value = "http://${azurerm_public_ip.mgmt_public_ip.ip_address}:8500"
  }  
}

#
# Create Azure log analytics workspace
#
resource "azurerm_log_analytics_workspace" "law" {
  name                = format("%s-law", local.student_id)
  sku                 = "PerNode"
  retention_in_days   = 300
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_log_analytics_solution" "sentinel" {
  solution_name         = "SecurityInsights"
  location              = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/SecurityInsights"
  }
}

#
#  Create ELK stack
#
resource "azurerm_public_ip" "elk_public_ip" {
  name                = "pip-mgmt-elk"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"   # Static is required due to the use of the Standard sku
  tags = {
    Name   = "pip-mgmt-elk"
    source = "terraform"
  }
}

resource "azurerm_network_interface" "elkvm-ext-nic" {
  name               = "${local.student_id}-elkvm-ext-nic"
  location           = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "primary"
    subnet_id                     =  data.azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.125"
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.elk_public_ip.id
  }

  tags = {
    Name        = "${local.student_id}-elkvm-ext-int"
    application = "elkserver"
    tag_name    = "Env"
    value       = "elk"
  }
}

resource "azurerm_virtual_machine" "elkvm" {
  name                  = "elkvm"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.elkvm-ext-nic.id]
  vm_size               = "Standard_DS3_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true
  
  storage_os_disk {
    name              = "elkvmOsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "elkvm"
    admin_username = "elkuser"
    admin_password = var.upassword
    custom_data    = file("elk.sh")

  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    Name                = "${local.student_id}-elkvm"
    tag_name            = "Env"
    value               = "elk"
    propagate_at_launch = true
  }
}