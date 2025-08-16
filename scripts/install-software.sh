#!/bin/bash

# Log all output to a file
exec > >(tee /var/log/install-software.log)
exec 2>&1

echo "Starting software installation at $(date)"

# Update package list
echo "Updating package list..."
apt-get update -y

# Install Python 3 and pip (if not already installed)
echo "Installing Python 3 and pip..."
apt-get install -y python3 python3-pip python3-venv

# Install Ansible
echo "Installing Ansible..."
apt-get install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible

# Install Java (required for Jenkins)
echo "Installing Java..."
apt-get install -y openjdk-11-jdk

# Add Jenkins repository and install Jenkins
echo "Installing Jenkins..."
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | apt-key add -
sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
apt-get update -y
apt-get install -y jenkins

# Start and enable Jenkins
echo "Starting Jenkins service..."
systemctl start jenkins
systemctl enable jenkins

# Install additional useful tools
echo "Installing additional tools..."
apt-get install -y git curl wget unzip

# Install Docker (often useful for CI/CD)
echo "Installing Docker..."
apt-get install -y apt-transport-https ca-certificates gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
usermod -aG docker $1

# Create a simple status file
echo "Installation completed at $(date)" > /tmp/installation-complete.txt

# Display versions
echo "=== Installed Software Versions ==="
python3 --version
pip3 --version
ansible --version
java -version
jenkins --version
docker --version

echo "Software installation completed successfully at $(date)"
echo "Jenkins initial admin password can be found at: /var/lib/jenkins/secrets/initialAdminPassword"
