#!/bin/bash

echo "🚀 Setting up Kafka RTI PoC VM..."

# Update system
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Docker
echo "🐳 Installing Docker..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
echo "🔧 Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add user to docker group
sudo usermod -aG docker $USER

# Install Azure CLI
echo "☁️ Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install additional tools
echo "🛠️ Installing additional tools..."
sudo apt install -y jq curl wget git

# Create directories
echo "📁 Creating project directories..."
mkdir -p ~/kafka-rti-poc/{docker,config,scripts,connectors}

# Clone the repository
echo "📥 Cloning project repository..."
cd ~
git clone https://github.com/vitaled/kafka-rti-private-connection-poc.git
cd kafka-rti-private-connection-poc

# Set permissions
chmod +x scripts/*.sh

echo "✅ VM setup completed!"
echo ""
echo "🔄 Please log out and log back in for Docker group changes to take effect"
echo "Then run: cd ~/kafka-rti-private-connection-poc && docker-compose -f docker/docker-compose.yml up -d"
