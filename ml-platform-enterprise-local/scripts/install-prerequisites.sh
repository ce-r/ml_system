#!/bin/bash
set -e

echo "Installing required tools..."

# Function to install tool if missing
install_if_missing() {
    local tool=$1
    local install_cmd=$2
    
    if ! command -v "$tool" &> /dev/null; then
        echo "Installing $tool..."
        eval "$install_cmd"
    else
        echo "✓ $tool already installed"
    fi
}

# Update package list first
sudo apt update

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Note: You may need to log out and back in for Docker permissions to take effect."
    # Start docker service
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "✓ Docker already installed"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "✓ kubectl already installed"
fi

# Install minikube
if ! command -v minikube &> /dev/null; then
    echo "Installing minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
else
    echo "✓ minikube already installed"
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo "✓ Terraform already installed"
fi

# Install Ansible
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
else
    echo "✓ Ansible already installed"
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "✓ Helm already installed"
fi

# Install other required packages
echo "Installing other required packages..."
sudo apt install -y jq git curl wget netcat-openbsd python3-pip python3-venv

# Install docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "Installing docker-compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "✓ docker-compose already installed"
fi

# Install Python packages in system Python (not in venv)
echo "Installing Python packages..."
python3 -m pip install --upgrade pip
python3 -m pip install awscli-local

echo "All prerequisites installed!"
