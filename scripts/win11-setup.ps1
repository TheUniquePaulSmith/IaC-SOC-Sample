# Windows 11 Configuration Script for SOC Lab
# This script installs Wazuh agent, configures SSH, and sets up firewall rules

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Create log file
$LogFile = "C:\temp\win11-setup.log"
New-Item -ItemType Directory -Force -Path "C:\temp"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "Starting Windows 11 SOC Lab configuration..."

try {
    # Install Chocolatey
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # Install OpenSSH Server
    Write-Log "Installing OpenSSH Server..."
    choco install openssh -y

    # Configure OpenSSH Server
    Write-Log "Configuring OpenSSH Server..."
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'

    # Configure SSH for public key authentication
    $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
    if (Test-Path $sshdConfigPath) {
        (Get-Content $sshdConfigPath) -replace '#PubkeyAuthentication yes', 'PubkeyAuthentication yes' | Set-Content $sshdConfigPath
        (Get-Content $sshdConfigPath) -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes' | Set-Content $sshdConfigPath
    }

    # Restart SSH service
    Restart-Service sshd

    # Configure Windows Firewall - Allow SSH
    Write-Log "Configuring Windows Firewall for SSH..."
    New-NetFirewallRule -DisplayName "SSH Inbound" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
    New-NetFirewallRule -DisplayName "SSH Outbound" -Direction Outbound -Protocol TCP -LocalPort 22 -Action Allow

    # Configure Windows Firewall - Allow VNET subnet traffic
    Write-Log "Configuring Windows Firewall for VNET subnet traffic..."
    New-NetFirewallRule -DisplayName "Allow VNET Subnet Inbound" -Direction Inbound -RemoteAddress "10.0.1.0/24" -Action Allow
    New-NetFirewallRule -DisplayName "Allow VNET Subnet Outbound" -Direction Outbound -RemoteAddress "10.0.1.0/24" -Action Allow

    # Wait for network connectivity
    Write-Log "Waiting for network connectivity..."
    Start-Sleep -Seconds 30

    # Download and install Wazuh agent
    Write-Log "Downloading Wazuh agent..."
    $wazuhAgentUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.12.0-1.msi"
    $wazuhAgentPath = "C:\temp\wazuh-agent.msi"
    
    # Download with retry logic
    $maxRetries = 3
    $retryCount = 0
    do {
        try {
            Invoke-WebRequest -Uri $wazuhAgentUrl -OutFile $wazuhAgentPath -UseBasicParsing
            Write-Log "Wazuh agent downloaded successfully"
            break
        }
        catch {
            $retryCount++
            Write-Log "Download attempt $retryCount failed: $($_.Exception.Message)"
            if ($retryCount -ge $maxRetries) {
                throw "Failed to download Wazuh agent after $maxRetries attempts"
            }
            Start-Sleep -Seconds 10
        }
    } while ($retryCount -lt $maxRetries)

    # Install Wazuh agent
    Write-Log "Installing Wazuh agent..."
    $wazuhServerIP = "${wazuh_server_ip}"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $wazuhAgentPath, "/quiet", "WAZUH_MANAGER=$wazuhServerIP" -Wait

    # Start Wazuh agent service
    Write-Log "Starting Wazuh agent service..."
    Start-Service -Name "WazuhSvc"
    Set-Service -Name "WazuhSvc" -StartupType Automatic

    # Configure additional firewall rules for Wazuh
    Write-Log "Configuring firewall rules for Wazuh agent..."
    New-NetFirewallRule -DisplayName "Wazuh Agent Outbound 1514" -Direction Outbound -Protocol TCP -RemotePort 1514 -Action Allow
    New-NetFirewallRule -DisplayName "Wazuh Agent Outbound 1515" -Direction Outbound -Protocol TCP -RemotePort 1515 -Action Allow

    # Install additional tools
    Write-Log "Installing additional tools..."
    choco install git -y
    choco install 7zip -y
    choco install notepadplusplus -y

    # Create completion marker
    Write-Log "Windows 11 configuration completed successfully!"
    "Windows 11 SOC Lab setup completed at $(Get-Date)" | Out-File -FilePath "C:\temp\setup-complete.txt"
    
    # Create info file with connection details
    @"
=== Windows 11 SOC Lab Information ===
Configuration completed: $(Get-Date)
SSH Status: $(Get-Service sshd | Select-Object -ExpandProperty Status)
Wazuh Agent Status: $(Get-Service WazuhSvc | Select-Object -ExpandProperty Status)
Wazuh Server: $wazuhServerIP
Admin Username: ${win11_admin_username}

Firewall Rules Configured:
- SSH (Port 22) - Inbound/Outbound
- VNET Subnet (10.0.1.0/24) - Full access
- Wazuh Agent (Ports 1514/1515) - Outbound

Services Installed:
- OpenSSH Server
- Wazuh Agent
- Git
- 7-Zip
- Notepad++
"@ | Out-File -FilePath "C:\temp\system-info.txt"

}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)"
    $_.Exception.Message | Out-File -FilePath "C:\temp\setup-error.txt"
    throw
}
