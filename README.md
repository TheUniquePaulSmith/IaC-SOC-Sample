# IaC-SOC-Sample
An automated SOC sample deployed as IaC in Azure

## Overview
This Infrastructure as Code (IaC) project deploys a complete Security Operations Center (SOC) lab environment in Microsoft Azure. The lab includes both Linux and Windows managed endpoints with integrated security monitoring through Wazuh SIEM.

## Architecture
The SOC lab consists of:
- **Control Node**: Ubuntu 22.04 LTS with Wazuh server, Jenkins CI/CD, Docker, and Ansible
- **Windows Target**: Windows 11 Enterprise with Wazuh agent and OpenSSH server
- **Network**: Single VNet (10.0.0.0/16) with shared subnet (10.0.1.0/24)
- **Security**: Network Security Group with service-specific access rules
- **Management**: Auto-shutdown functionality for cost optimization

## Prerequisites
- Azure CLI installed and authenticated
- Terraform installed (version 0.12+)
- SSH key pair for Linux VM access

## Quick Start
1. Clone this repository
2. Copy `terraform.tfvars.example` to `terraform.tfvars`
3. Update variables in `terraform.tfvars` with your values
4. Deploy the infrastructure:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Infrastructure Components

### Control Node (Ubuntu 22.04)
- **Services**: Wazuh SIEM, Jenkins, Docker, Ansible
- **Access**: SSH (port 22), Web UI (ports 8080, 9200, 5601)
- **Configuration**: Automated via cloud-init script

### Windows Target (Windows 11 Enterprise)
- **Services**: Wazuh agent, OpenSSH server
- **Access**: RDP (port 3389), SSH (port 22), WinRM (ports 5985/5986)
- **Configuration**: Automated via PowerShell script

### Network Security
- Source IP restriction for external access
- Intra-VNet communication allowed
- Service-specific port rules

## Configuration Files

### Required Files
- `terraform.tfvars` - Your deployment configuration
- `scripts/cloud-init.yaml` - Linux VM setup script
- `scripts/win11-setup.ps1` - Windows VM setup script

### Optional Files
- `scripts/cloud-init-basic.yaml` - Minimal Linux setup
- Custom cloud-init or PowerShell scripts

## Outputs
After deployment, Terraform provides:
- Public and private IP addresses
- SSH/RDP connection strings
- Web service URLs
- Network configuration details

## Management
Both VMs include auto-shutdown functionality (configurable time/timezone) to minimize costs when not in use.

For detailed auto-shutdown configuration, see: [Auto-Shutdown Configuration Guide](docs/auto-shutdown-guide.md)

## Troubleshooting
Check the scripts directory for cloud-init and PowerShell logs if deployment issues occur.
