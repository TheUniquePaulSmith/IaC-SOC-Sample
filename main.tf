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
  
  # Windows 11 setup script with Wazuh server IP substitution  
  win11_setup_script = templatefile("${path.module}/scripts/win11-setup.ps1", {
    wazuh_server_ip    = azurerm_network_interface.nic.private_ip_address
    win11_admin_username = var.win11_admin_username
  })
  
  # Create a base64 encoded version of the script to avoid escaping issues
  win11_script_b64 = base64encode(local.win11_setup_script)
  
  # Create a simple bootstrap command that decodes and executes the script
  win11_bootstrap_command = "powershell -ExecutionPolicy Unrestricted -Command \"New-Item -ItemType Directory -Force -Path 'C:\\\\temp'; [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${local.win11_script_b64}')) | Out-File -FilePath 'C:\\\\temp\\\\win11-setup.ps1' -Encoding UTF8; & 'C:\\\\temp\\\\win11-setup.ps1'\""
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

  security_rule {
    name                       = "RDP"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WinRM-HTTP"
    priority                   = 1007
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WinRM-HTTPS"
    priority                   = 1008
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = local.ssh_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH-Windows"
    priority                   = 1009
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.ssh_source_ip
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

# Create Windows 11 public IP
resource "azurerm_public_ip" "win11_public_ip" {
  name                = var.windows_public_ip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Windows 11 network interface
resource "azurerm_network_interface" "win11_nic" {
  name                = var.windows_network_interface_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.win11_public_ip.id
  }
}

# Create Windows 11 VM with custom script extension
resource "azurerm_virtual_machine" "win11_vm" {
  name                  = var.win11_vm_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.win11_nic.id]
  vm_size               = var.win11_vm_size

  storage_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-22h2-ent"
    version   = "latest"
  }

  storage_os_disk {
    name              = var.win11_os_disk_name
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  os_profile {
    computer_name  = var.win11_vm_name
    admin_username = var.win11_admin_username
    admin_password = var.win11_admin_password
  }

  os_profile_windows_config {
    provision_vm_agent = true
  }

  tags = {
    Environment = "SOC-Lab"
    Purpose     = "Managed-Target"
    OS          = "Windows-11"
  }
}

# Windows 11 VM Extension for custom script execution
resource "azurerm_virtual_machine_extension" "win11_setup" {
  name                 = "win11-setup"
  virtual_machine_id   = azurerm_virtual_machine.win11_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = []
  })

  protected_settings = jsonencode({
    commandToExecute = local.win11_bootstrap_command
  })

  depends_on = [azurerm_virtual_machine.control_vm]
}

# Auto-shutdown configuration for Windows 11 VM
resource "azurerm_resource_group_template_deployment" "win11_auto_shutdown" {
  count               = var.auto_shutdown_enabled ? 1 : 0
  name                = "auto-shutdown-${var.win11_vm_name}"
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
        "name": "shutdown-computevm-${azurerm_virtual_machine.win11_vm.name}",
        "location": azurerm_resource_group.rg.location,
        "properties": {
          "status": "Enabled",
          "taskType": "ComputeVmShutdownTask",
          "dailyRecurrence": {
            "time": var.auto_shutdown_time
          },
          "timeZoneId": var.auto_shutdown_timezone,
          "targetResourceId": azurerm_virtual_machine.win11_vm.id,
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
    vm_type = "windows"
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

## OUTPUTS

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

# Windows 11 VM outputs
output "win11_vm_public_ip" {
  value = azurerm_public_ip.win11_public_ip.ip_address
  description = "Public IP address of the Windows 11 VM"
}

output "win11_vm_private_ip" {
  value = azurerm_network_interface.win11_nic.private_ip_address
  description = "Private IP address of the Windows 11 VM within the VNet"
}

output "win11_vm_fqdn" {
  value = "${azurerm_virtual_machine.win11_vm.name}.${azurerm_resource_group.rg.location}.cloudapp.azure.com"
  description = "Fully Qualified Domain Name of the Windows 11 VM"
}

output "win11_rdp_connection" {
  value = "mstsc /v:${azurerm_public_ip.win11_public_ip.ip_address}"
  description = "RDP connection string for Windows 11 VM"
}

output "win11_ssh_connection" {
  value = "ssh ${var.win11_admin_username}@${azurerm_public_ip.win11_public_ip.ip_address}"
  description = "SSH connection string for Windows 11 VM"
}

output "windows_network_info" {
  value = {
    public_ip    = azurerm_public_ip.win11_public_ip.ip_address
    private_ip   = azurerm_network_interface.win11_nic.private_ip_address
    fqdn         = "${azurerm_virtual_machine.win11_vm.name}.${azurerm_resource_group.rg.location}.cloudapp.azure.com"
    vm_name      = azurerm_virtual_machine.win11_vm.name
    admin_user   = var.win11_admin_username
    wazuh_server = azurerm_network_interface.nic.private_ip_address
  }
  description = "Complete network information for the Windows 11 VM"
}
