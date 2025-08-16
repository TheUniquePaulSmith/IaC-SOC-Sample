variable "azure_region" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "My-Lab"
}

variable "control_vm_name" {
  description = "Name of the control virtual machine"
  type        = string
  default     = "controlNode1"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D4as_v6" #this is 4 vcpus with 17GiB RAM
}

variable "admin_username" {
  description = "Administrator username for the virtual machine"
  type        = string
  default     = "adminuser"
}

variable "admin_password" {
  description = "Administrator password for the virtual machine"
  type        = string
  sensitive   = true
  
  validation {
    condition = length(var.admin_password) >= 8 && can(regex("[A-Z]", var.admin_password)) && can(regex("[a-z]", var.admin_password)) && can(regex("[0-9]", var.admin_password)) && can(regex("[^A-Za-z0-9]", var.admin_password))
    error_message = "Password must be at least 8 characters long and contain uppercase, lowercase, numeric, and special characters."
  }
}

variable "os_disk_name" {
  description = "Name of the OS disk"
  type        = string
  default     = "controlNodeDisk1"
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "lab-vnet"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "internal-subnet"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "control_network_interface_name" {
  description = "Name of the control network interface"
  type        = string
  default     = "control-nic"
}

variable "control_public_ip_name" {
  description = "Name of the control public IP"
  type        = string
  default     = "control-public-ip"
}

variable "windows_network_interface_name" {
  description = "Name of the windows network interface"
  type        = string
  default     = "windows-nic"
}

variable "windows_public_ip_name" {
  description = "Name of the windows public IP"
  type        = string
  default     = "windows-public-ip"
}

variable "nsg_name" {
  description = "Name of the Network Security Group"
  type        = string
  default     = "lab-nsg"
}

variable "ssh_source_address_prefix" {
  description = "Source IP address prefix allowed for SSH access (use * for any, or specify your public IP like 203.0.113.1/32)"
  type        = string
  default     = "*"
}

variable "cloud_init_script_path" {
  description = "Path to the cloud-init script file"
  type        = string
  default     = "scripts/cloud-init.yaml"
}

variable "auto_shutdown_time" {
  description = "Time to automatically shutdown the VM (24-hour format, e.g., '0700' for 7:00 AM)"
  type        = string
  default     = "0700"
}

variable "auto_shutdown_timezone" {
  description = "Timezone for the auto-shutdown schedule"
  type        = string
  default     = "CST"
}

variable "auto_shutdown_enabled" {
  description = "Enable automatic VM shutdown"
  type        = bool
  default     = true
}

variable "auto_shutdown_notification_email" {
  description = "Email address for shutdown notifications (optional)"
  type        = string
  default     = ""
}