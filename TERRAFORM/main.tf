# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
    features {}
}

# Create a resource group
resource "azurerm_resource_group" "resource_group" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags = {
    environment = "Development"
  }
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Development"
  }
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "nic" {
  for_each              = toset(var.instances)
  name                = "${var.prefix}-${each.key}-nic"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "${var.prefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    environment = "Development"
  }
}

# Create a network public IP
resource "azurerm_public_ip" "publicip" {
  name                = "${var.prefix}-publicip"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"

  tags = {
    environment = "Development"
  }
}

# Create a load balancer
resource "azurerm_lb" "lb" {
  name                = "${var.prefix}-lb"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.publicip.id
  }

  tags = {
    environment = "Development"
  }
}

# Create a address pool
resource "azurerm_lb_backend_address_pool" "lb_adr_pool" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "nic_adr_pool_acc" {
  for_each              = toset(var.instances)
  network_interface_id    = azurerm_network_interface.nic[format("%s", each.key)].id
  ip_configuration_name   = "${var.prefix}-ipconfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_adr_pool.id
}

# Create a network security group
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  security_rule {
    name                        = "AllowVNetInboundTraffic"
    priority                    = 4080
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "*"
    source_port_range           = "*"
    destination_port_range      = "*"
    source_address_prefix       = "10.0.0.0/16"
    destination_address_prefix  = "10.0.0.0/16"
    #resource_group_name         = azurerm_resource_group.resource_group.name
    #network_security_group_name = azurerm_network_security_group.nsg.name
  }

  security_rule {
    name                        = "DenyAllOtherInbound"
    priority                    = 4090
    direction                   = "Inbound"
    access                      = "Deny"
    protocol                    = "*"
    source_port_range           = "*"
    destination_port_range      = "*"
    source_address_prefix       = "0.0.0.0/0"
    destination_address_prefix  = "10.0.0.0/16"
    #resource_group_name         = azurerm_resource_group.resource_group.name
    #network_security_group_name = azurerm_network_security_group.nsg.name
  }

  tags = {
    environment = "Development"
  }
}

# Create a virtual machine availability set
resource "azurerm_availability_set" "aset" {
  name                = "${var.prefix}-aset"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  tags = {
    environment = "Development"
  }
}

# Get the custom image created by Packer
data "azurerm_image" "myPackerImage" {
  name = "myPackerImage"
  resource_group_name = "myResourceGroup"
}

resource "azurerm_virtual_machine" "vm" {
  #count                 = var.vm_count
  #name                  = "${var.prefix}-vm${count.index}"
  for_each              = toset(var.instances)
  name                  = "${var.prefix}-${each.key}"
  location              = azurerm_resource_group.resource_group.location
  resource_group_name   = azurerm_resource_group.resource_group.name
  availability_set_id   = azurerm_availability_set.aset.id
  #network_interface_ids = [azurerm_network_interface.nic.id]
  network_interface_ids = [azurerm_network_interface.nic[format("%s", each.key)].id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    #publisher = "Canonical"
    #offer     = "UbuntuServer"
    #sku       = "16.04-LTS"
    #version   = "latest"
    id = data.azurerm_image.myPackerImage.id
  }

  storage_os_disk {
    name              = "${each.key}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = var.vm_username
    admin_password = var.vm_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    environment = "Development"
  }
}

resource "azurerm_managed_disk" "managed_disk" {
  #count                = var.vm_count
  #name                 = "${var.prefix}-disk${count.index}"
  for_each              = toset(var.instances)
  name                  = "${var.prefix}-${each.key}-disk"
  location             = azurerm_resource_group.resource_group.location
  resource_group_name  = azurerm_resource_group.resource_group.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 10

  tags = {
    environment = "Development"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "managed_disk_attach" {
  #managed_disk_id    = azurerm_managed_disk.managed_disk[count.index].id
  #virtual_machine_id = azurerm_virtual_machine.vm[count.index].id
  for_each              = toset(var.instances)
  managed_disk_id    = azurerm_managed_disk.managed_disk[each.key].id
  virtual_machine_id = azurerm_virtual_machine.vm[element(split("_", each.key), 1)].id
  lun                = "10"
  caching            = "ReadWrite"
}