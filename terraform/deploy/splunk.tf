  resource "azurerm_public_ip" "splunk_public_ip" {
  name                = "pip-mgmt-splunk"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"   # Static is required due to the use of the Standard sku
  tags = {
    Name   = "pip-mgmt-splunk"
    source = "terraform"
  }
}

resource "azurerm_network_interface" "splunkvm-ext-nic" {
  name               = "${local.student_id}-splunkvm-ext-nic"
  location           = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "primary"
    subnet_id                     =  data.azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.135"
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.splunk_public_ip.id
  }

  tags = {
    Name        = "${local.student_id}-splunkvm-ext-int"
    application = "splunkserver"
    tag_name    = "Env"
    value       = "splunk"
  }
}

resource "azurerm_virtual_machine" "splunkvm" {
  name                  = "splunkvm"
  depends_on            = [local_file.splunk]
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.splunkvm-ext-nic.id]
  vm_size               = "Standard_DS3_v2"

  storage_os_disk {
    name              = "splunkvmOsDisk"
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
    computer_name  = "splunkvm"
    admin_username = "splunkuser"
    admin_password = var.upassword
    custom_data    = file("./splunk.sh")

  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    Name                = "${local.student_id}-splunkvm"
    tag_name            = "Env"
    value               = "splunk"
    propagate_at_launch = true
  }
}

