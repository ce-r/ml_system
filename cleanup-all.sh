#!/bin/bash

echo "=== Complete System Reset for ML Platform ==="

# 1. Stop all services
echo "Stopping all services..."
sudo systemctl stop docker
sudo systemctl stop containerd 2>/dev/null || true

# 2. Kill all processes
echo "Killing all related processes..."
sudo pkill -f "docker" || true
sudo pkill -f "containerd" || true
sudo pkill -f "minikube" || true
sudo pkill -f "kubectl" || true
sudo pkill -f "uvicorn" || true
sudo pkill -f "app:app" || true
sudo pkill -f "fastapi" || true
sudo pkill -f "python.*ml-platform" || true

# 3. Kill all port forwards
echo "Stopping kubectl port forwards..."
pkill -f "kubectl port-forward" || true

# 4. Clean up Minikube completely
echo "Cleaning Minikube..."
minikube stop 2>/dev/null || true
minikube delete --all --purge 2>/dev/null || true
docker stop minikube 2>/dev/null || true
docker rm -f minikube 2>/dev/null || true
rm -rf ~/.minikube
rm -rf ~/.kube/config
sudo rm -rf /root/.minikube 2>/dev/null || true
sudo rm -rf /etc/kubernetes 2>/dev/null || true

# 5. Free up all ports
echo "Freeing up ports..."
for port in 8000 8200 8201 9090 3000 5432 6379 27017 9000 9001 9092 2181 32770 32780 8443 22 2376 5000 32443; do
    sudo fuser -k $port/tcp 2>/dev/null || true
done

# 6. Clean Docker containers and volumes
echo "Cleaning Docker containers..."
docker-compose -f infrastructure/docker/docker-compose.yml down -v 2>/dev/null || true
docker-compose -f infrastructure/docker/docker-compose-redis-enhanced.yml down -v 2>/dev/null || true

# Stop all ML platform containers
for container in $(docker ps -a --filter "name=ml-" --format "{{.Names}}"); do
    echo "Stopping container: $container"
    docker stop $container 2>/dev/null || true
    docker rm $container 2>/dev/null || true
done

# 7. Reset iptables completely
echo "Resetting iptables..."
# Save current rules just in case
sudo iptables-save > ~/iptables-backup-$(date +%Y%m%d-%H%M%S).txt

# Flush all rules
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Reset ip6tables too
sudo ip6tables -F
sudo ip6tables -X
sudo ip6tables -t nat -F
sudo ip6tables -t nat -X
sudo ip6tables -t mangle -F
sudo ip6tables -t mangle -X
sudo ip6tables -P INPUT ACCEPT
sudo ip6tables -P FORWARD ACCEPT
sudo ip6tables -P OUTPUT ACCEPT

# 8. Clean Docker completely
echo "Cleaning Docker..."
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
sudo rm -rf /var/run/docker*
sudo rm -rf /var/lib/containerd

# 9. Reinstall Docker iptables rules
echo "Reinstalling Docker..."
sudo apt-get update
sudo apt-get install --reinstall docker.io docker-compose -y

# 10. Configure Docker properly
echo "Configuring Docker..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "userland-proxy": true,
  "debug": false,
  "log-level": "info",
  "storage-driver": "overlay2",
  "insecure-registries": ["localhost:32770", "localhost:32780"]
}
EOF

# 11. Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf

# 12. Load necessary kernel modules
echo "Loading kernel modules..."
sudo modprobe br_netfilter
sudo modprobe overlay
echo "br_netfilter" | sudo tee -a /etc/modules
echo "overlay" | sudo tee -a /etc/modules

# 13. Start Docker fresh
echo "Starting Docker..."
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker

# 14. Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
for i in {1..30}; do
    if sudo docker info >/dev/null 2>&1; then
        echo "Docker is ready!"
        break
    fi
    echo -n "."
    sleep 1
done

# 15. Create required iptables chains for Docker
echo "Creating Docker iptables chains..."
sudo iptables -t filter -N DOCKER 2>/dev/null || true
sudo iptables -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
sudo iptables -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
sudo iptables -t filter -N DOCKER-USER 2>/dev/null || true
sudo iptables -t nat -N DOCKER 2>/dev/null || true

# 16. Add user to docker group (if needed)
sudo usermod -aG docker $USER

# 17. Clean any remaining files
echo "Cleaning remaining files..."
rm -rf ~/ml-platform-enterprise-local/infrastructure/terraform/.terraform*
rm -rf ~/ml-platform-enterprise-local/infrastructure/terraform/terraform.tfstate*
rm -f test-*.sh monitor-*.sh inspect-*.sh check-*.sh quick-*.sh create-*.sh debug-*.sh

# 18. Clean Docker networks
echo "Cleaning Docker networks..."
docker network rm minikube 2>/dev/null || true
docker network rm ml-network 2>/dev/null || true
docker network prune -f

# 19. Clean Docker volumes
echo "Cleaning Docker volumes..."
docker volume rm ml-platform-data ml-platform-models 2>/dev/null || true
docker volume prune -f

# 20. Verify Docker is working
echo -e "\nVerifying Docker..."
sudo docker run --rm hello-world

# 21. Final cleanup of any remaining processes
echo "Final cleanup..."
sudo netstat -tlnp 2>/dev/null | grep -E ":(8000|9090|3000|5432|6379|27017|9000|9001|8443)" | awk '{print $7}' | cut -d'/' -f1 | xargs -r sudo kill -9 2>/dev/null || true

echo ""
echo "=== System Reset Complete! ==="
echo ""
echo "IMPORTANT: You need to log out and log back in for group changes to take effect."
echo "After logging back in, run:"
echo "  cd ~/ml_sys_deploy"
echo "  ./run-enterprise-ml-platform-local.sh"
echo ""
echo "If you still have issues, reboot your system with:"
echo "  sudo reboot"



# #!/bin/bash

# echo "=== Complete System Reset for ML Platform ==="

# # 1. Stop all services
# echo "Stopping all services..."
# sudo systemctl stop docker
# sudo systemctl stop containerd 2>/dev/null || true

# # 2. Kill all processes
# echo "Killing all related processes..."
# sudo pkill -f "docker" || true
# sudo pkill -f "containerd" || true
# sudo pkill -f "minikube" || true
# sudo pkill -f "kubectl" || true

# # 3. Clean up Minikube
# echo "Cleaning Minikube..."
# rm -rf ~/.minikube
# rm -rf ~/.kube/config
# sudo rm -rf /root/.minikube 2>/dev/null || true
# sudo rm -rf /etc/kubernetes 2>/dev/null || true

# # 4. Reset iptables completely
# echo "Resetting iptables..."
# # Save current rules just in case
# sudo iptables-save > ~/iptables-backup-$(date +%Y%m%d-%H%M%S).txt

# # Flush all rules
# sudo iptables -F
# sudo iptables -X
# sudo iptables -t nat -F
# sudo iptables -t nat -X
# sudo iptables -t mangle -F
# sudo iptables -t mangle -X
# sudo iptables -P INPUT ACCEPT
# sudo iptables -P FORWARD ACCEPT
# sudo iptables -P OUTPUT ACCEPT

# # Reset ip6tables too
# sudo ip6tables -F
# sudo ip6tables -X
# sudo ip6tables -t nat -F
# sudo ip6tables -t nat -X
# sudo ip6tables -t mangle -F
# sudo ip6tables -t mangle -X
# sudo ip6tables -P INPUT ACCEPT
# sudo ip6tables -P FORWARD ACCEPT
# sudo ip6tables -P OUTPUT ACCEPT

# # 5. Clean Docker completely
# echo "Cleaning Docker..."
# sudo rm -rf /var/lib/docker
# sudo rm -rf /etc/docker
# sudo rm -rf /var/run/docker*
# sudo rm -rf /var/lib/containerd

# # 6. Reinstall Docker iptables rules
# echo "Reinstalling Docker..."
# sudo apt-get update
# sudo apt-get install --reinstall docker.io docker-compose -y

# # 7. Configure Docker properly
# echo "Configuring Docker..."
# sudo mkdir -p /etc/docker
# cat <<EOF | sudo tee /etc/docker/daemon.json
# {
#   "iptables": true,
#   "ip-forward": true,
#   "ip-masq": true,
#   "userland-proxy": true,
#   "debug": false,
#   "log-level": "info",
#   "storage-driver": "overlay2"
# }
# EOF

# # 8. Enable IP forwarding
# echo "Enabling IP forwarding..."
# sudo sysctl -w net.ipv4.ip_forward=1
# sudo sysctl -w net.ipv6.conf.all.forwarding=1
# echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
# echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf

# # 9. Load necessary kernel modules
# echo "Loading kernel modules..."
# sudo modprobe br_netfilter
# sudo modprobe overlay
# echo "br_netfilter" | sudo tee -a /etc/modules
# echo "overlay" | sudo tee -a /etc/modules

# # 10. Start Docker fresh
# echo "Starting Docker..."
# sudo systemctl daemon-reload
# sudo systemctl enable docker
# sudo systemctl start docker

# # 11. Wait for Docker to be ready
# echo "Waiting for Docker to be ready..."
# for i in {1..30}; do
#     if sudo docker info >/dev/null 2>&1; then
#         echo "Docker is ready!"
#         break
#     fi
#     echo -n "."
#     sleep 1
# done

# # 12. Add user to docker group (if needed)
# sudo usermod -aG docker $USER

# # 13. Clean any remaining files
# echo "Cleaning remaining files..."
# rm -rf ~/ml-platform-enterprise-local/infrastructure/terraform/.terraform*
# rm -rf ~/ml-platform-enterprise-local/infrastructure/terraform/terraform.tfstate*
# rm -f test-*.sh monitor-*.sh inspect-*.sh check-*.sh

# # 14. Verify Docker is working
# echo -e "\nVerifying Docker..."
# sudo docker run --rm hello-world

# # 15. Reset Docker networks
# echo "Resetting Docker networks..."
# sudo docker network prune -f
# sudo docker network ls

# echo ""
# echo "=== System Reset Complete! ==="
# echo ""
# echo "IMPORTANT: You need to log out and log back in for group changes to take effect."
# echo "After logging back in, run:"
# echo "  cd ~/ml_sys_deploy"
# echo "  ./run-enterprise-ml-platform-local.sh"
# echo ""
# echo "If you still have issues, reboot your system with:"
# echo "  sudo reboot"

# #!/bin/bash

# echo "=== Complete ML Platform Cleanup ==="

# # 1. Kill all API processes
# echo "Stopping API processes..."
# sudo pkill -f "uvicorn" || true
# sudo pkill -f "app:app" || true
# sudo pkill -f "fastapi" || true
# sudo pkill -f "python.*ml-platform" || true

# # 2. Kill all port forwards
# echo "Stopping kubectl port forwards..."
# pkill -f "kubectl port-forward" || true

# # 3. Delete Kubernetes resources
# echo "Cleaning Kubernetes resources..."
# kubectl delete namespace ml-platform --force --grace-period=0 2>/dev/null || true
# kubectl delete namespace monitoring --force --grace-period=0 2>/dev/null || true

# # 4. Stop and delete Minikube cluster
# echo "Cleaning up Minikube..."
# minikube stop || true
# minikube delete --all --purge || true

# # 5. Clean Docker resources
# echo "Stopping Docker containers..."
# docker-compose -f infrastructure/docker/docker-compose.yml down -v 2>/dev/null || true
# docker-compose -f infrastructure/docker/docker-compose-redis-enhanced.yml down -v 2>/dev/null || true

# # Stop all ML platform containers
# for container in $(docker ps -a --filter "name=ml-" --format "{{.Names}}"); do
#     echo "Stopping container: $container"
#     docker stop $container 2>/dev/null || true
#     docker rm $container 2>/dev/null || true
# done

# # Remove the minikube container if it exists
# docker stop minikube 2>/dev/null || true
# docker rm minikube 2>/dev/null || true

# # 6. Clean up Docker volumes
# echo "Cleaning Docker volumes..."
# docker volume rm ml-platform-data ml-platform-models 2>/dev/null || true
# docker volume prune -f 2>/dev/null || true

# # 7. Clean up Docker networks
# echo "Cleaning Docker networks..."
# docker network rm ml-network 2>/dev/null || true
# docker network prune -f 2>/dev/null || true

# # 8. Free up all ports
# echo "Freeing up ports..."
# for port in 8000 8200 8201 9090 3000 5432 6379 27017 9000 9001 9092 2181 32770 32780 8443; do
#     sudo fuser -k $port/tcp 2>/dev/null || true
# done

# # 9. Clean Terraform state
# echo "Cleaning Terraform state..."
# if [ -d "infrastructure/terraform" ]; then
#     cd infrastructure/terraform
#     rm -rf .terraform terraform.tfstate* .terraform.lock.hcl 2>/dev/null || true
#     cd ../..
# fi

# # 10. Clean Minikube config
# echo "Cleaning Minikube configuration..."
# rm -rf ~/.minikube/cache 2>/dev/null || true
# rm -rf ~/.minikube/profiles/minikube 2>/dev/null || true

# # 11. Reset Docker daemon (if needed)
# echo "Checking Docker daemon..."
# sudo systemctl restart docker 2>/dev/null || true

# # 12. Clean kubectl context
# echo "Cleaning kubectl context..."
# kubectl config delete-context minikube 2>/dev/null || true
# kubectl config delete-cluster minikube 2>/dev/null || true
# kubectl config delete-user minikube 2>/dev/null || true

# # 13. Remove temporary files
# echo "Cleaning temporary files..."
# rm -f test-*.sh monitor-*.sh inspect-*.sh check-*.sh quick-*.sh create-*.sh debug-*.sh 2>/dev/null || true

# # 14. Final cleanup of any remaining processes
# echo "Final cleanup..."
# sudo netstat -tlnp 2>/dev/null | grep -E ":(8000|9090|3000|5432|6379|27017|9000|9001|8443)" | awk '{print $7}' | cut -d'/' -f1 | xargs -r sudo kill -9 2>/dev/null || true

# # 15. Clean iptables rules left by Docker/Kubernetes
# echo "Cleaning iptables rules..."
# sudo iptables -t nat -F 2>/dev/null || true
# sudo iptables -t mangle -F 2>/dev/null || true
# sudo iptables -F 2>/dev/null || true
# sudo iptables -X 2>/dev/null || true

# # sudo docker system prune -a --volumes

# echo ""
# echo "=== Cleanup complete! ==="
# echo ""
# echo "System is clean. You can now run:"
# echo "./run-enterprise-ml-platform-local.sh"
# echo ""
# echo "If you still have issues, try:"
# echo "1. docker system prune -a --volumes"
# echo "2. sudo systemctl restart docker"
# echo "3. Reboot your system"


# #!/bin/bash

# echo "=== Stopping all ML Platform services ==="

# # 1. Kill all API processes
# echo "Stopping API processes..."
# sudo pkill -f "uvicorn"
# sudo pkill -f "app:app"
# sudo pkill -f "fastapi"

# # 2. Kill all port forwards
# echo "Stopping kubectl port forwards..."
# pkill -f "kubectl port-forward"

# # 3. Free up all ports used by the platform
# echo "Freeing up ports..."
# for port in 8000 8200 8201 9090 3000 5432 6379 27017 9000 9001 9092 2181 32770; do
#     sudo fuser -k $port/tcp 2>/dev/null || true
# done

# # 4. Stop all Docker containers
# echo "Stopping Docker containers..."
# docker-compose -f infrastructure/docker/docker-compose.yml down 2>/dev/null || true
# docker-compose -f infrastructure/docker/docker-compose-redis-enhanced.yml down 2>/dev/null || true

# # Stop individual containers if compose doesn't work
# for container in ml-postgres-primary ml-postgres-replica ml-redis-master ml-redis-replica-1 ml-redis-replica-2 ml-mongodb ml-minio ml-zookeeper ml-kafka ml-redisinsight ml-redis-exporter ml-prometheus ml-grafana ml-vault ml-registry ml-api; do
#     docker stop $container 2>/dev/null || true
#     docker rm $container 2>/dev/null || true
# done

# # 5. Stop Minikube
# echo "Stopping Minikube..."
# minikube stop 2>/dev/null || true

# # 6. Clean up Docker volumes (optional - removes all data)
# echo "Cleaning Docker volumes..."
# docker volume prune -f 2>/dev/null || true

# # 7. Remove any Python processes that might be hanging
# echo "Cleaning Python processes..."
# pkill -f "python.*ml-platform" 2>/dev/null || true

# # 8. Clean up any remaining processes on key ports
# echo "Final port cleanup..."
# sudo netstat -tlnp 2>/dev/null | grep -E ":(8000|9090|3000|5432|6379|27017|9000|9001)" | awk '{print $7}' | cut -d'/' -f1 | xargs -r sudo kill -9 2>/dev/null || true

# # 9. Remove temporary files
# echo "Cleaning temporary files..."
# rm -f test-*.sh monitor-*.sh inspect-*.sh check-*.sh quick-*.sh create-*.sh debug-*.sh 2>/dev/null || true

# echo ""
# echo "=== Cleanup complete! ==="
# echo ""
# echo "All services stopped. You can now run your master script:"
# echo "./run-enterprise-ml-platform-local.sh"
