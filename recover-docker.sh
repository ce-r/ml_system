#!/bin/bash

echo "=== Docker Recovery Script ==="

# Remove broken Docker
echo "Removing broken Docker installation..."
sudo systemctl stop docker 2>/dev/null || true
sudo apt-get remove --purge -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo rm -rf /var/lib/docker /etc/docker
sudo rm -f /etc/apparmor.d/docker
sudo groupdel docker 2>/dev/null || true
sudo rm -rf /var/run/docker.sock

# Clean up
sudo apt-get autoremove -y
sudo apt-get autoclean

# Install Docker properly
echo "Installing Docker..."
sudo apt-get update
sudo apt-get install -y docker.io docker-compose

# Create docker group and add user
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker $USER

# Start Docker
echo "Starting Docker..."
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker

# Wait for Docker
sleep 5

# Test
echo "Testing Docker..."
sudo docker run --rm hello-world

echo -e "\nDocker recovered! Log out and back in for group permissions."
echo "Then run: ./run-enterprise-ml-platform-local.sh"