# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Data source to get current public IP (optional - can be overridden by variable)
data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

# Local values for cloud-init script
locals {
  # Use the variable if provided, otherwise fall back to auto-detected IP
  ssh_source_ip = var.ssh_source_address_prefix != "*" ? var.ssh_source_address_prefix : "${chomp(data.http.myip.response_body)}/32"
  
  # Load cloud-init script from external file and substitute variables
  cloud_init_script = templatefile("${path.module}/${var.cloud_init_script_path}", {
    admin_username = var.admin_username
  })
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.azure_region
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Create Network Security Group and rules
resource "azurerm_network_security_group" "nsg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Jenkins"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WazuhDashboard"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WazuhAgent"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1514"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WazuhAgentAuth"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1515"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group to Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create control public IP
resource "azurerm_public_ip" "control_public_ip" {
  name                = var.control_public_ip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  name                = var.control_network_interface_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.control_public_ip.id
  }
}

# Create the Control Node VM
resource "azurerm_virtual_machine" "control_vm" {
  name                  = var.control_vm_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = var.vm_size

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  storage_os_disk {
    name              = var.os_disk_name
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  os_profile {
    computer_name  = var.control_vm_name
    admin_username = var.admin_username
    admin_password = var.admin_password
    custom_data    = base64encode(local.cloud_init_script)
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

# Auto-shutdown configuration for the VM
resource "azurerm_resource_group_template_deployment" "vm_auto_shutdown" {
  count               = var.auto_shutdown_enabled ? 1 : 0
  name                = "auto-shutdown-${var.control_vm_name}"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
      {
        "type": "Microsoft.DevTestLab/schedules",
        "apiVersion": "2018-09-15",
        "name": "shutdown-computevm-${azurerm_virtual_machine.control_vm.name}",
        "location": azurerm_resource_group.rg.location,
        "properties": {
          "status": "Enabled",
          "taskType": "ComputeVmShutdownTask",
          "dailyRecurrence": {
            "time": var.auto_shutdown_time
          },
          "timeZoneId": var.auto_shutdown_timezone,
          "targetResourceId": azurerm_virtual_machine.control_vm.id,
          "notificationSettings": {
            "status": var.auto_shutdown_notification_email != "" ? "Enabled" : "Disabled",
            "emailRecipient": var.auto_shutdown_notification_email,
            "timeInMinutes": 30
          }
        }
      }
    ]
  })

  tags = {
    environment = "lab"
    auto_shutdown = "enabled"
  }
}

# Output the public IP for easy access
output "control_vm_public_ip" {
  value = azurerm_public_ip.control_public_ip.ip_address
  description = "Public IP address of the control VM"
}

# Output the Jenkins URL
output "jenkins_url" {
  value = "http://${azurerm_public_ip.control_public_ip.ip_address}:8080"
  description = "Jenkins URL - use this to access Jenkins web interface"
}

output "wazuh_dashboard_url" {
  value = "https://${azurerm_public_ip.control_public_ip.ip_address}:443"
  description = "Wazuh Dashboard URL - use this to access Wazuh SIEM web interface"
}

output "wazuh_server_ip" {
  value = azurerm_public_ip.control_public_ip.ip_address
  description = "Wazuh Server IP - use this IP to configure Wazuh agents"
}

output "control_vm_fqdn" {
  value = "${azurerm_virtual_machine.control_vm.name}.${azurerm_resource_group.rg.location}.cloudapp.azure.com"
  description = "Fully Qualified Domain Name of the control VM"
}

output "control_vm_private_ip" {
  value = azurerm_network_interface.nic.private_ip_address
  description = "Private IP address of the control VM within the VNet"
}

output "vm_network_info" {
  value = {
    public_ip    = azurerm_public_ip.control_public_ip.ip_address
    private_ip   = azurerm_network_interface.nic.private_ip_address
    fqdn         = "${azurerm_virtual_machine.control_vm.name}.${azurerm_resource_group.rg.location}.cloudapp.azure.com"
    vm_name      = azurerm_virtual_machine.control_vm.name
    location     = azurerm_resource_group.rg.location
  }
  description = "Complete network information for the control VM"
}

output "auto_shutdown_info" {
  value = var.auto_shutdown_enabled ? {
    enabled       = true
    shutdown_time = var.auto_shutdown_time
    timezone      = var.auto_shutdown_timezone
    notification  = var.auto_shutdown_notification_email != "" ? "Enabled" : "Disabled"
  } : {
    enabled = false
  }
  description = "Auto-shutdown configuration for the VM"
}
