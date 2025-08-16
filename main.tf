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
  features {}
}

# Local values for cloud-init script
locals {
  cloud_init_script = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    
    packages:
      - python3
      - python3-pip
      - python3-venv
      - software-properties-common
      - openjdk-11-jdk
      - git
      - curl
      - wget
      - unzip
      - apt-transport-https
      - ca-certificates
      - gnupg
      - lsb-release
    
    runcmd:
      # Install Ansible
      - add-apt-repository --yes --update ppa:ansible/ansible
      - apt-get update -y
      - apt-get install -y ansible
      
      # Install Jenkins
      - wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo apt-key add -
      - sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
      - apt-get update -y
      - apt-get install -y jenkins
      - systemctl start jenkins
      - systemctl enable jenkins
      
      # Install Docker
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      - echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      - apt-get update -y
      - apt-get install -y docker-ce docker-ce-cli containerd.io
      - usermod -aG docker ${var.admin_username}
      
      # Create status file
      - echo "Installation completed at $(date)" > /tmp/installation-complete.txt
      - echo "Jenkins initial admin password location: /var/lib/jenkins/secrets/initialAdminPassword" >> /tmp/installation-complete.txt
      
    write_files:
      - path: /tmp/software-versions.sh
        content: |
          #!/bin/bash
          echo "=== Installed Software Versions ==="
          python3 --version
          pip3 --version
          ansible --version
          java -version
          jenkins --version
          docker --version
        permissions: '0755'
    
    final_message: "Software installation completed successfully!"
  EOF
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
    source_address_prefix      = var.ssh_source_address_prefix
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
    source_address_prefix      = var.ssh_source_address_prefix
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

# Output the public IP for easy access
output "control_vm_public_ip" {
  value = azurerm_public_ip.control_public_ip.ip_address
  description = "Public IP address of the control VM"
}

output "jenkins_url" {
  value = "http://${azurerm_public_ip.control_public_ip.ip_address}:8080"
  description = "Jenkins URL - use this to access Jenkins web interface"
}
