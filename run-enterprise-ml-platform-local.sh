#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration 
export PROJECT_DIR="$HOME/ml-platform-enterprise-local"
export ENVIRONMENT="local"
export KUBECONFIG="$HOME/.kube/config"

echo -e "${PURPLE}================================================${NC}"
echo -e "${PURPLE}   ML Platform Enterprise - Local Deployment${NC}"
echo -e "${PURPLE}   Full Complexity, Zero Cost${NC}"
echo -e "${PURPLE}================================================${NC}"

# Check if we're in a virtual environment and exit if so
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo -e "${RED}Error: This script cannot run inside a virtual environment.${NC}"
    echo -e "${YELLOW}Please run 'deactivate' first, then run this script again.${NC}"
    exit 1
fi

# Function to check command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service
wait_for_service() {
    local service=$1
    # local namespace=${2:-default}
    local namespace=$2
    local max_attempts=60
    local attempt=1
    
    echo -e "${YELLOW}Waiting for $service to be ready...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pods -n $namespace -l app=$service 2>/dev/null | grep -q "Running"; then
            echo -e "${GREEN}$service is ready${NC}"
            return 0
        fi
        sleep 5
        ((attempt++))
    done
    echo -e "${RED}$service failed to start${NC}"
    return 1
}

# Step 1: Create project structure
echo -e "\n${BLUE}Step 1: Creating project structure...${NC}"
mkdir -p $PROJECT_DIR/{scripts,infrastructure/{terraform,ansible,kubernetes,docker},services,monitoring,tests}
cd $PROJECT_DIR

# Step 2: Install prerequisites
echo -e "\n${BLUE}Step 2: Installing prerequisites...${NC}"

# Create prerequisite installation script
cat > scripts/install-prerequisites.sh << 'PREREQ_EOF'
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
        echo "$tool already installed"
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
    echo "Docker already installed"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "kubectl already installed"
fi

# Install minikube
if ! command -v minikube &> /dev/null; then
    echo "Installing minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
else
    echo "minikube already installed"
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo "Terraform already installed"
fi

# Install Ansible
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
else
    echo "Ansible already installed"
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm already installed"
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
PREREQ_EOF

chmod +x scripts/install-prerequisites.sh
./scripts/install-prerequisites.sh


# Step 2.5: Configure Docker connection
echo -e "\n${BLUE}Step 2.5: Configuring Docker connection...${NC}"

# First, fix Docker if it's in a failed state
if systemctl is-failed docker >/dev/null 2>&1; then
    echo "Docker is in failed state. Attempting to fix..."
    
    # Remove conflicting configurations
    sudo rm -f /etc/docker/daemon.json
    
    # Recreate the TCP configuration that was working before
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/override.conf << 'EOF' > /dev/null

[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://127.0.0.1:2375
EOF
    
    # Reload and restart
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    sleep 5
fi

# Set Docker to use TCP
export DOCKER_HOST=tcp://127.0.0.1:2375

# Ensure Docker is running
if ! docker ps >/dev/null 2>&1; then
    echo "Starting Docker service..."
    sudo systemctl start docker
    sleep 5
fi

# Final check
if docker ps >/dev/null 2>&1; then
    echo "Docker is running and accessible via TCP at $DOCKER_HOST"
else
    echo -e "${RED}Error: Cannot connect to Docker.${NC}"
    echo "Please check Docker manually with: sudo systemctl status docker"
    exit 1
fi


# Step 3: Setup Minikube
echo -e "\n${BLUE}Step 3: Setting up Minikube...${NC}"

# Check if current user is in docker group
if ! groups | grep -q docker; then
    echo -e "${YELLOW}Adding current user to docker group...${NC}"
    sudo usermod -aG docker $USER
    echo -e "${YELLOW}You need to log out and back in for Docker permissions.${NC}"
    echo -e "${YELLOW}After logging back in, run this script again.${NC}"
    exit 1 
fi

# Check if minikube is running --memory=8192, --disk-size=40g
if ! minikube status >/dev/null 2>&1; then
    echo "Starting minikube..."
    minikube start \
        --cpus=4 \
        --memory=4096 \
        --disk-size=30g \
        --driver=docker \
        --kubernetes-version=v1.28.0
else
    echo "Minikube already running"
fi

# Enable addons
echo "Enabling minikube addons..."
minikube addons enable ingress
minikube addons enable ingress-dns
minikube addons enable metrics-server
minikube addons enable dashboard
minikube addons enable registry
minikube addons enable storage-provisioner

# Step 4: Create Terraform configuration
echo -e "\n${BLUE}Step 4: Creating Terraform configuration...${NC}"

mkdir -p infrastructure/terraform
cat > infrastructure/terraform/main.tf << 'TF_EOF'
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Create namespaces
resource "kubernetes_namespace" "ml_platform" {
  metadata {
    name = "ml-platform"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# resource "kubernetes_namespace" "ingress" {
#   metadata {
#     name = "ingress-nginx"
#   }
# }

# Modify the resource to use data source and use existing ingress-nginx namespace created by minikube
data "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

# Local storage class
resource "kubernetes_storage_class" "local_storage" {
  metadata {
    name = "local-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}

# Docker volumes for persistent storage
resource "docker_volume" "ml_data" {
  name = "ml-platform-data"
}

resource "docker_volume" "ml_models" {
  name = "ml-platform-models"
}

output "namespace" {
  value = kubernetes_namespace.ml_platform.metadata[0].name
}
TF_EOF

# Step 5: Create Ansible configuration
echo -e "\n${BLUE}Step 5: Creating Ansible configuration...${NC}"

mkdir -p infrastructure/ansible
cat > infrastructure/ansible/inventory.yml << 'ANSIBLE_EOF'
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
ANSIBLE_EOF

cat > infrastructure/ansible/playbook.yml << 'PLAYBOOK_EOF'
---
- name: Setup ML Platform Infrastructure
  hosts: localhost
  become: yes
  vars:
    ml_platform_dir: "{{ lookup('env', 'PROJECT_DIR') }}"
    
  tasks:
    - name: Ensure Docker is running
      systemd:
        name: docker
        state: started
        enabled: yes
    
    - name: Create required directories
      file:
        path: "{{ ml_platform_dir }}/{{ item }}"
        state: directory
        mode: '0755'
        owner: "{{ ansible_user_id }}"
        group: "{{ ansible_user_id }}"
      loop:
        - data/postgres
        - data/redis
        - data/mongodb
        - data/minio
        - data/models
        - logs
        - configs
        - secrets
    
    - name: Generate secrets
      shell: |
        openssl rand -base64 32 > {{ ml_platform_dir }}/secrets/jwt_secret
        openssl rand -base64 32 > {{ ml_platform_dir }}/secrets/db_password
        openssl rand -base64 32 > {{ ml_platform_dir }}/secrets/redis_password
      args:
        creates: "{{ ml_platform_dir }}/secrets/jwt_secret"
    
    - name: Set permissions on secrets
      file:
        path: "{{ ml_platform_dir }}/secrets"
        state: directory
        mode: '0700'
        owner: "{{ ansible_user_id }}"
        group: "{{ ansible_user_id }}"
        recurse: yes
    
    - name: Create Docker network
      docker_network:
        name: ml-platform-network
    
    - name: Install Python docker module for Ansible
      apt:
        name: python3-docker
        state: present
        update_cache: yes
PLAYBOOK_EOF

# Step 6: Create infrastructure services
echo -e "\n${BLUE}Step 6: Creating infrastructure services...${NC}"

mkdir -p infrastructure/docker
cat > infrastructure/docker/docker-compose.yml << 'DOCKER_EOF'
version: '3.8'

services:
  # PostgreSQL with replication
  postgres-primary:
    image: postgres:15-alpine
    container_name: ml-postgres-primary
    environment:
      POSTGRES_DB: mlplatform
      POSTGRES_USER: mluser
      POSTGRES_PASSWORD: mlpass123
      POSTGRES_REPLICATION_MODE: master
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: reppass123
    volumes:
      - postgres_primary:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - ml-platform-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mluser"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis
  redis-master:
    image: redis:7-alpine
    container_name: ml-redis-master
    command: redis-server --requirepass redispass123
    ports:
      - "6379:6379"
    volumes:
      - redis_master:/data
    networks:
      - ml-platform-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "redispass123", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MongoDB
  mongodb:
    image: mongo:6
    container_name: ml-mongodb
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: mongopass123
      MONGO_INITDB_DATABASE: mlplatform
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    networks:
      - ml-platform-network
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/test --quiet
      interval: 10s
      timeout: 5s
      retries: 5

  # Kafka & Zookeeper
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: ml-zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    networks:
      - ml-platform-network

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    container_name: ml-kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    networks:
      - ml-platform-network

  # MinIO with S3 compatible storage
  minio:
    image: minio/minio:latest
    container_name: ml-minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    networks:
      - ml-platform-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # Vault for secrets
  vault:
    # image: vault:latest
    image: hashicorp/vault:1.15
    container_name: ml-vault
    cap_add:
      - IPC_LOCK 
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: myroot
      VAULT_DEV_LISTEN_ADDRESS: 0.0.0.0:8200
    ports:
      - "8200:8200"
    networks:
      - ml-platform-network

networks:
  ml-platform-network:
    external: true

volumes:
  postgres_primary:
  redis_master:
  mongodb_data:
  minio_data:
DOCKER_EOF

# Step 6.5: Create Enhanced Redis Setup
echo -e "\n${BLUE}Step 6.5: Creating enhanced Redis configuration...${NC}"

# Create Redis configuration file
cat > infrastructure/docker/redis.conf << 'REDIS_CONF_EOF'
# Redis configuration for ML Platform

# Network
bind 0.0.0.0
protected-mode no
port 6379

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Replication
replica-read-only yes

# Security
requirepass redispass123
masterauth redispass123

# Limits
maxclients 10000

# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru

# Append only mode
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no

# Lua scripting
lua-time-limit 32770

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Event notification
notify-keyspace-events ""

# Advanced config
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100

# Active rehashing
activerehashing yes

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Frequency
hz 10

# AOF rewrite
aof-rewrite-incremental-fsync yes

# RDB
rdb-save-incremental-fsync yes
REDIS_CONF_EOF

# Create enhanced Redis docker-compose
cat > infrastructure/docker/docker-compose-redis-enhanced.yml << 'REDIS_DOCKER_EOF'
version: '3.8'

services:
  # Redis Master with full configuration
  redis-master:
    image: redis:7-alpine
    container_name: ml-redis-master
    command: redis-server /usr/local/etc/redis/redis.conf
    ports:
      - "6379:6379"
    volumes:
      - redis_master:/data
      - ./redis.conf:/usr/local/etc/redis/redis.conf
    networks:
      - ml-platform-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "redispass123", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Replica 1
  redis-replica-1:
    image: redis:7-alpine
    container_name: ml-redis-replica-1
    command: redis-server --slaveof redis-master 6379 --masterauth redispass123 --requirepass redispass123
    ports:
      - "6380:6379"
    volumes:
      - redis_replica_1:/data
    networks:
      - ml-platform-network
    depends_on:
      redis-master:
        condition: service_healthy

  # Redis Replica 2
  redis-replica-2:
    image: redis:7-alpine
    container_name: ml-redis-replica-2
    command: redis-server --slaveof redis-master 6379 --masterauth redispass123 --requirepass redispass123
    ports:
      - "6381:6379"
    volumes:
      - redis_replica_2:/data
    networks:
      - ml-platform-network
    depends_on:
      redis-master:
        condition: service_healthy

  # Redis Sentinel 1
  redis-sentinel-1:
    image: redis:7-alpine
    container_name: ml-redis-sentinel-1
    command: redis-sentinel /etc/redis-sentinel/sentinel.conf
    ports:
      - "26379:26379"
    volumes:
      - ./sentinel1.conf:/etc/redis-sentinel/sentinel.conf
    networks:
      - ml-platform-network
    depends_on:
      - redis-master
      - redis-replica-1
      - redis-replica-2

  # RedisInsight for GUI management
  redisinsight:
    image: redislabs/redisinsight:latest
    container_name: ml-redisinsight
    ports:
      - "8001:8001"
    volumes:
      - redisinsight:/db
    networks:
      - ml-platform-network

  # Redis Exporter for Prometheus
  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: ml-redis-exporter
    environment:
      REDIS_ADDR: redis-master:6379
      REDIS_PASSWORD: redispass123
    ports:
      - "9121:9121"
    networks:
      - ml-platform-network
    depends_on:
      - redis-master

networks:
  ml-platform-network:
    external: true

volumes:
  redis_master:
  redis_replica_1:
  redis_replica_2:
  redisinsight:
REDIS_DOCKER_EOF

# Create Sentinel configuration
cat > infrastructure/docker/sentinel1.conf << 'SENTINEL_EOF'
port 26379
bind 0.0.0.0
sentinel monitor mymaster redis-master 6379 2
sentinel auth-pass mymaster redispass123
sentinel down-after-milliseconds mymaster 32770
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000
SENTINEL_EOF

# Step 7: Create Kubernetes manifests
echo -e "\n${BLUE}Step 7: Creating Kubernetes manifests...${NC}"

mkdir -p infrastructure/kubernetes

# Create ML Platform deployment
cat > infrastructure/kubernetes/ml-platform-deployment.yml << 'K8S_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-platform-api
  namespace: ml-platform
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ml-platform-api
  template:
    metadata:
      labels:
        app: ml-platform-api
    spec:
      containers:
      - name: api
        image: localhost:32770/ml-platform:latest
        imagePullPolicy: Never 
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_URL
          value: "postgresql://mluser:mlpass123@host.minikube.internal:5432/mlplatform"
        - name: REDIS_URL
          value: "redis://:redispass123@host.minikube.internal:6379"
        - name: MONGODB_URL
          # value: "mongodb://admin:mongopass123@host.docker.internal:27017/mlplatform?authSource=admin&directConnection=true"
          # value: "mongodb://admin:mongopass123@host.minikube.internal:27017/mlplatform"
          value: "mongodb://admin:mongopass123@host.minikube.internal:27017/mlplatform?authSource=admin"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "host.minikube.internal:9092"
        - name: MINIO_ENDPOINT
          value: "host.minikube.internal:9000"
        - name: MINIO_ACCESS_KEY
          value: "minioadmin"
        - name: MINIO_SECRET_KEY
          value: "minioadmin123"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: ml-platform-api
  namespace: ml-platform
spec:
  selector:
    app: ml-platform-api
  ports:
  - port: 8000
    targetPort: 8000
  type: NodePort
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ml-platform-ingress
  namespace: ml-platform
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: ml-platform.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ml-platform-api
            port:
              number: 8000
K8S_EOF

# Create Redis Kubernetes resources
cat > infrastructure/kubernetes/redis-k8s.yml << 'REDIS_K8S_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: ml-platform
data:
  redis.conf: |
    maxmemory 2gb
    maxmemory-policy allkeys-lru
    appendonly yes
    appendfsync everysec
    requirepass redispass123
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ml-platform
spec:
  serviceName: redis
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command:
          - redis-server
          - /etc/redis/redis.conf
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: config
          mountPath: /etc/redis
        - name: data
          mountPath: /data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: redis-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ml-platform
spec:
  clusterIP: None
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
---
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  namespace: ml-platform
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
    statefulset.kubernetes.io/pod-name: redis-0
REDIS_K8S_EOF

# Create monitoring stack
cat > infrastructure/kubernetes/monitoring.yml << 'MON_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
    - job_name: 'ml-platform'
      static_configs:
      - targets: ['ml-platform-api.ml-platform.svc.cluster.local:8000']
    - job_name: 'redis'
      static_configs:
      - targets: ['host.minikube.internal:9121']
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: data
          mountPath: /prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
  type: NodePort
MON_EOF

# Step 8: Create ML Platform application
echo -e "\n${BLUE}Step 8: Creating ML Platform application...${NC}"

mkdir -p services/ml-platform
cat > services/ml-platform/Dockerfile << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKERFILE_EOF

# Create requirements.txt
cat > services/ml-platform/requirements.txt << 'REQ_EOF'
fastapi==0.104.1
uvicorn==0.24.0
pandas==2.1.3
numpy==1.24.3
scikit-learn==1.3.2
redis==5.0.1
asyncpg==0.29.0
pydantic==2.5.0
python-multipart==0.0.6
PyJWT==2.8.0
httpx==0.25.2
prometheus-client==0.19.0
motor==3.1.2
pymongo==4.3.3
minio==7.2.0
aiokafka==0.10.0
joblib==1.3.2
REQ_EOF

# Create a comprehensive app.py
cat > services/ml-platform/app.py << 'APP_EOF'
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import redis 
import asyncpg
import motor.motor_asyncio
from datetime import datetime, timedelta
import os
import json
import jwt
import numpy as np
from sklearn.ensemble import RandomForestClassifier
import joblib
import io
from minio import Minio
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response
import asyncio
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="ML Platform API", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://mluser:mlpass123@localhost:5432/mlplatform")
REDIS_URL = os.getenv("REDIS_URL", "redis://:redispass123@localhost:6379")
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://admin:mongopass123@localhost:27017/mlplatform")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "localhost:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin123")
JWT_SECRET = os.getenv("JWT_SECRET", "your-secret-key")

# Metrics
request_count = Counter('ml_platform_requests_total', 'Total requests', ['method', 'endpoint'])
request_duration = Histogram('ml_platform_request_duration_seconds', 'Request duration')
model_training_counter = Counter('ml_platform_model_training_total', 'Total model trainings')
prediction_counter = Counter('ml_platform_predictions_total', 'Total predictions')

# Initialize connections
redis_client = redis.from_url(REDIS_URL, decode_responses=True)
mongo_client = motor.motor_asyncio.AsyncIOMotorClient(MONGODB_URL)
mongo_db = mongo_client.mlplatform

# MinIO client
minio_client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=False
)

# Models
class UserCreate(BaseModel):
    username: str
    email: str
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

class ModelTrainRequest(BaseModel):
    name: str
    model_type: str
    dataset_id: str
    parameters: Dict[str, Any]

class PredictionRequest(BaseModel):
    data: List[List[float]]

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    services: Dict[str, str]

class FeatureStoreRequest(BaseModel):
    feature_set: str
    features: Dict[str, Any]

# Database initialization
async def init_db():
    conn = await asyncpg.connect(DATABASE_URL)
    await conn.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(255) UNIQUE NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            password VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    await conn.execute('''
        CREATE TABLE IF NOT EXISTS models (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            model_type VARCHAR(100) NOT NULL,
            user_id INTEGER REFERENCES users(id),
            status VARCHAR(50) DEFAULT 'training',
            accuracy FLOAT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    await conn.execute('''
        CREATE TABLE IF NOT EXISTS predictions (
            id SERIAL PRIMARY KEY,
            model_id INTEGER REFERENCES models(id),
            user_id INTEGER REFERENCES users(id),
            input_data JSONB,
            prediction JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    await conn.close()

@app.on_event("startup")
async def startup():
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL)
    await init_db()
    
    # Ensure MinIO buckets exist
    for bucket in ["models", "datasets", "features"]:
        if not minio_client.bucket_exists(bucket):
            minio_client.make_bucket(bucket)
    
    logger.info("ML Platform API started successfully")

@app.on_event("shutdown")
async def shutdown():
    await app.state.db_pool.close()
    logger.info("ML Platform API shutdown")

# Helper functions
def create_token(user_id: int) -> str:
    payload = {
        "user_id": user_id,
        "exp": datetime.utcnow() + timedelta(hours=24)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")

async def get_current_user(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    
    token = authorization.split(" ")[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        return payload["user_id"]
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

# Endpoints
@app.get("/health", response_model=HealthResponse)
async def health_check():
    services = {
        "api": "up",
        "postgres": "unknown",
        "redis": "unknown",
        "mongodb": "unknown",
        "minio": "unknown"
    }
    
    # Check PostgreSQL
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        services["postgres"] = "up"
    except:
        services["postgres"] = "down"
    
    # Check Redis
    try:
        redis_client.ping()
        services["redis"] = "up"
    except:
        services["redis"] = "down"
    
    # Check MongoDB
    try:
        await mongo_db.command("ping")
        services["mongodb"] = "up"
    except:
        services["mongodb"] = "down"
    
    # Check MinIO
    try:
        minio_client.list_buckets()
        services["minio"] = "up"
    except:
        services["minio"] = "down"
    
    return HealthResponse(
        status="healthy" if all(s == "up" for s in services.values()) else "degraded",
        timestamp=datetime.utcnow().isoformat(),
        services=services
    )

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type="text/plain")

@app.post("/api/v1/auth/register")
async def register(user: UserCreate):
    request_count.labels(method="POST", endpoint="/api/v1/auth/register").inc()
    
    async with app.state.db_pool.acquire() as conn:
        try:
            # Simple password hashing (use bcrypt in production)
            hashed_password = f"hashed_{user.password}"
            
            result = await conn.fetchrow(
                "INSERT INTO users (username, email, password) VALUES (\$1, \$2, \$3) RETURNING id",
                user.username, user.email, hashed_password
            )
            
            user_id = result["id"]
            token = create_token(user_id)
            
            # Cache user session in Redis
            redis_client.setex(f"session:{user_id}", 86400, token)
            
            return {"user_id": user_id, "access_token": token}
        except asyncpg.UniqueViolationError:
            raise HTTPException(status_code=400, detail="User already exists")

@app.post("/api/v1/auth/login")
async def login(user: UserLogin):
    request_count.labels(method="POST", endpoint="/api/v1/auth/login").inc()
    
    async with app.state.db_pool.acquire() as conn:
        result = await conn.fetchrow(
            "SELECT id, password FROM users WHERE username = \$1",
            user.username
        )
        
        if not result or result["password"] != f"hashed_{user.password}":
            raise HTTPException(status_code=401, detail="Invalid credentials")
        
        token = create_token(result["id"])
        
        # Cache user session in Redis
        redis_client.setex(f"session:{result['id']}", 86400, token)
        
        return {"access_token": token}

@app.post("/api/v1/models/train")
async def train_model(request: ModelTrainRequest, user_id: int = Depends(get_current_user)):
    request_count.labels(method="POST", endpoint="/api/v1/models/train").inc()
    model_training_counter.inc()
    
    async with app.state.db_pool.acquire() as conn:
        result = await conn.fetchrow(
            "INSERT INTO models (name, model_type, user_id) VALUES (\$1, \$2, \$3) RETURNING id",
            request.name, request.model_type, user_id
        )
        
        model_id = result["id"]
        
        # Simulate model training (in production, this would be async)
        if request.model_type == "classification":
            model = RandomForestClassifier(
                n_estimators=request.parameters.get("n_estimators", 100),
                max_depth=request.parameters.get("max_depth", None),
                random_state=42
            )
            
            # Dummy training data
            X = np.random.rand(1000, 10)
            y = np.random.randint(0, 2, 1000)
            model.fit(X, y)
            
            # Calculate dummy accuracy
            accuracy = model.score(X, y)
            
            # Save model to MinIO
            model_buffer = io.BytesIO()
            joblib.dump(model, model_buffer)
            model_buffer.seek(0)
            
            minio_client.put_object(
                "models",
                f"model_{model_id}.pkl",
                model_buffer,
                length=model_buffer.getbuffer().nbytes
            )
            
            # Update model status and accuracy
            await conn.execute(
                "UPDATE models SET status = 'completed', accuracy = \$1 WHERE id = \$2",
                accuracy, model_id
            )
            
            # Cache model info in Redis
            model_info = {
                "id": model_id,
                "name": request.name,
                "type": request.model_type,
                "accuracy": accuracy,
                "status": "completed"
            }
            redis_client.setex(
                f"model:{model_id}",
                3600,
                json.dumps(model_info)
            )
            
            # Store training metadata in MongoDB
            await mongo_db.training_logs.insert_one({
                "model_id": model_id,
                "user_id": user_id,
                "parameters": request.parameters,
                "accuracy": accuracy,
                "timestamp": datetime.utcnow()
            })
        
        return {"model_id": model_id, "status": "training_started"}

@app.get("/api/v1/models/{model_id}")
async def get_model(model_id: int, user_id: int = Depends(get_current_user)):
    request_count.labels(method="GET", endpoint="/api/v1/models/{model_id}").inc()
    
    # Check cache first
    cached = redis_client.get(f"model:{model_id}")
    if cached:
        return json.loads(cached)
    
    async with app.state.db_pool.acquire() as conn:
        result = await conn.fetchrow(
            "SELECT * FROM models WHERE id = \$1 AND user_id = \$2",
            model_id, user_id
        )
        
        if not result:
            raise HTTPException(status_code=404, detail="Model not found")
        
        return dict(result)

@app.post("/api/v1/models/{model_id}/predict")
async def predict(model_id: int, request: PredictionRequest, user_id: int = Depends(get_current_user)):
    request_count.labels(method="POST", endpoint="/api/v1/models/{model_id}/predict").inc()
    prediction_counter.inc()
    
    # Check prediction cache
    cache_key = f"prediction:{model_id}:{hash(str(request.data))}"
    cached_prediction = redis_client.get(cache_key)
    if cached_prediction:
        return json.loads(cached_prediction)
    
    # Load model from MinIO
    try:
        response = minio_client.get_object("models", f"model_{model_id}.pkl")
        model = joblib.load(io.BytesIO(response.read()))
        
        # Make predictions
        predictions = model.predict(request.data)
        prediction_proba = model.predict_proba(request.data).tolist()
        
        result = {
            "predictions": predictions.tolist(),
            "probabilities": prediction_proba
        }
        
        # Cache prediction
        redis_client.setex(cache_key, 300, json.dumps(result))
        
        # Store prediction in MongoDB
        await mongo_db.predictions.insert_one({
            "model_id": model_id,
            "user_id": user_id,
            "input": request.data,
            "predictions": predictions.tolist(),
            "probabilities": prediction_proba,
            "timestamp": datetime.utcnow()
        })
        
        # Store in PostgreSQL
        async with app.state.db_pool.acquire() as conn:
            await conn.execute(
                "INSERT INTO predictions (model_id, user_id, input_data, prediction) VALUES (\$1, \$2, \$3, \$4)",
                model_id, user_id, json.dumps(request.data), json.dumps(result)
            )
        
        return result
    except Exception as e:
        logger.error(f"Prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@app.get("/api/v1/models")
async def list_models(user_id: int = Depends(get_current_user)):
    request_count.labels(method="GET", endpoint="/api/v1/models").inc()
    
    async with app.state.db_pool.acquire() as conn:
        results = await conn.fetch(
            "SELECT * FROM models WHERE user_id = \$1 ORDER BY created_at DESC",
            user_id
        )
        
        return {"models": [dict(r) for r in results]}

@app.post("/api/v1/features/store")
async def store_features(request: FeatureStoreRequest, user_id: int = Depends(get_current_user)):
    request_count.labels(method="POST", endpoint="/api/v1/features/store").inc()
    
    # Store in Redis for fast access
    redis_key = f"features:{request.feature_set}:{user_id}"
    redis_client.hset(redis_key, mapping=request.features)
    redis_client.expire(redis_key, 86400)  # 24 hours
    
    # Store in MongoDB for persistence
    await mongo_db.features.insert_one({
        "feature_set": request.feature_set,
        "user_id": user_id,
        "features": request.features,
        "timestamp": datetime.utcnow()
    })
    
    return {"status": "stored", "feature_set": request.feature_set}

@app.get("/api/v1/features/{feature_set}")
async def get_features(feature_set: str, user_id: int = Depends(get_current_user)):
    request_count.labels(method="GET", endpoint="/api/v1/features/{feature_set}").inc()
    
    # Check Redis first
    redis_key = f"features:{feature_set}:{user_id}"
    features = redis_client.hgetall(redis_key)
    
    if features:
        return {"feature_set": feature_set, "features": features, "source": "cache"}
    
    # Check MongoDB
    result = await mongo_db.features.find_one({
        "feature_set": feature_set,
        "user_id": user_id
    })
    
    if result:
        # Restore to Redis
        redis_client.hset(redis_key, mapping=result["features"])
        redis_client.expire(redis_key, 86400)
        
        return {
            "feature_set": feature_set,
            "features": result["features"],
            "source": "database"
        }
    
    raise HTTPException(status_code=404, detail="Feature set not found")

@app.get("/")
async def root():
    return {
        "message": "ML Platform Enterprise API",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
        "metrics": "/metrics"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
APP_EOF

# Step 9: Run Ansible playbook
echo -e "\n${BLUE}Step 9: Running Ansible configuration...${NC}"
cd infrastructure/ansible
ansible-playbook -i inventory.yml playbook.yml
cd ../..

# Step 10: Initialize Terraform
echo -e "\n${BLUE}Step 10: Initializing Terraform...${NC}"
cd infrastructure/terraform
terraform init
terraform plan
terraform apply -auto-approve
cd ../..

# Step 11: Start infrastructure services
echo -e "\n${BLUE}Step 11: Starting infrastructure services...${NC}"
cd infrastructure/docker
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Wait for services to be healthy
echo "Checking service health..."
for service in postgres-primary redis-master mongodb minio; do
    echo -n "Waiting for $service..."
    while ! docker-compose ps | grep $service | grep -q "healthy\|Up"; do
        sleep 5
        echo -n "."
    done
    echo " Ready!"
done

# Start enhanced Redis setup
echo -e "\n${BLUE}Starting enhanced Redis setup...${NC}"
docker-compose -f docker-compose-redis-enhanced.yml up -d
cd ../..

# Step 12: Build and push ML Platform image
echo -e "\n${BLUE}Step 12: Building ML Platform image...${NC}"
cd services/ml-platform

# Build and tag image for minikube's registry ADDED
eval $(minikube docker-env)  # This sets Docker to use minikube's Docker daemon

# Build and push image // localhost does not exist in minikube
docker build -t localhost:32770/ml-platform:latest .

# Reset docker env ADDED
eval $(minikube docker-env -u)

cd ../..

# Step 13: Deploy to Kubernetes
echo -e "\n${BLUE}Step 13: Deploying to Kubernetes...${NC}" 
kubectl apply -f infrastructure/kubernetes/ml-platform-deployment.yml
kubectl apply -f infrastructure/kubernetes/redis-k8s.yml
kubectl apply -f infrastructure/kubernetes/monitoring.yml 

# Wait for deployments
wait_for_service "ml-platform-api" "ml-platform"
wait_for_service "redis" "ml-platform"
wait_for_service "prometheus" "monitoring"
wait_for_service "grafana" "monitoring"

# Step 14: Setup port forwarding for easy access
echo -e "\n${BLUE}Step 14: Setting up port forwarding...${NC}"

# Kill any existing port-forward processes
pkill -f "kubectl port-forward" || true

# Start port forwarding in background
kubectl port-forward -n ml-platform svc/ml-platform-api 8000:8000 > /dev/null 2>&1 &
kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &
kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &

sleep 5

# Step 15: Initialize MinIO buckets
echo -e "\n${BLUE}Step 15: Initializing storage buckets...${NC}"
docker run --rm --network ml-platform-network \
    minio/mc alias set myminio http://minio:9000 minioadmin minioadmin123

for bucket in models datasets features; do
    docker run --rm --network ml-platform-network \
        minio/mc mb myminio/$bucket || true
done

# Step 16: Create Redis test scripts
echo -e "\n${BLUE}Step 16: Creating Redis test scripts...${NC}"

# Create comprehensive Redis test script
cat > test-redis-comprehensive.sh << 'REDIS_TEST_EOF'
#!/bin/bash

echo "=== Comprehensive Redis Testing ==="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Redis connection details
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASS="redispass123"

# Helper function
redis_cmd() {
    docker exec ml-redis-master redis-cli -a $REDIS_PASS "$@"
}

echo -e "\n${BLUE}1. Testing Basic Connectivity${NC}"
if redis_cmd ping | grep -q PONG; then
    echo -e "${GREEN}Redis is responding${NC}"
else
    echo -e "${RED}Redis is not responding${NC}"
    exit 1
fi

echo -e "\n${BLUE}2. Testing Data Types${NC}"

# Strings
echo "Testing Strings..."
redis_cmd SET test:string "Hello Redis"
redis_cmd GET test:string

# Lists
echo -e "\nTesting Lists..."
redis_cmd LPUSH test:list "item1" "item2" "item3"
redis_cmd LRANGE test:list 0 -1

# Sets
echo -e "\nTesting Sets..."
redis_cmd SADD test:set "member1" "member2" "member3"
redis_cmd SMEMBERS test:set

# Sorted Sets
echo -e "\nTesting Sorted Sets..."
redis_cmd ZADD test:zset 1 "one" 2 "two" 3 "three"
redis_cmd ZRANGE test:zset 0 -1 WITHSCORES

# Hashes
echo -e "\nTesting Hashes..."
redis_cmd HSET test:hash field1 "value1" field2 "value2"
redis_cmd HGETALL test:hash

# Streams
echo -e "\nTesting Streams..."
redis_cmd XADD test:stream "*" field1 value1 field2 value2
redis_cmd XRANGE test:stream - +

echo -e "\n${BLUE}3. Testing Pub/Sub${NC}"
# Start subscriber in background
docker exec -d ml-redis-master redis-cli -a $REDIS_PASS SUBSCRIBE test:channel
sleep 1
# Publish message
redis_cmd PUBLISH test:channel "Hello Subscribers"

echo -e "\n${BLUE}4. Testing Transactions${NC}"
redis_cmd MULTI
redis_cmd SET test:tx1 "value1"
redis_cmd SET test:tx2 "value2"
redis_cmd EXEC

echo -e "\n${BLUE}5. Testing Lua Scripting${NC}"
SCRIPT='return redis.call("SET", KEYS[1], ARGV[1])'
redis_cmd EVAL "$SCRIPT" 1 test:lua "Lua Value"
redis_cmd GET test:lua

echo -e "\n${BLUE}6. Testing Persistence${NC}"
redis_cmd BGSAVE
sleep 2
redis_cmd LASTSAVE

echo -e "\n${BLUE}7. Testing Replication${NC}"
redis_cmd INFO replication

echo -e "\n${BLUE}8. Testing Memory Usage${NC}"
redis_cmd INFO memory | grep -E "used_memory_human|used_memory_peak_human"

echo -e "\n${BLUE}9. Testing Performance${NC}"
echo "Running benchmark..."
docker run --rm --network ml-platform-network redis:7-alpine \
    redis-benchmark -h redis-master -a $REDIS_PASS -t set,get -n 10000 -q

echo -e "\n${BLUE}10. Testing ML-Specific Use Cases${NC}"

# Feature Store
echo -e "\nSetting up Feature Store..."
redis_cmd HSET "features:user:1001" \
    "age" "25" \
    "location" "NYC" \
    "purchase_count" "42" \
    "last_login" "2024-01-15"

redis_cmd HGETALL "features:user:1001"

# Model Cache
echo -e "\nCaching ML Model Metadata..."
MODEL_JSON='{"id":"model_123","name":"fraud_detector","version":"1.0","accuracy":0.95}'
redis_cmd SET "model:fraud_detector:latest" "$MODEL_JSON" EX 3600
redis_cmd GET "model:fraud_detector:latest"

# Real-time Predictions Cache
echo -e "\nCaching Predictions..."
redis_cmd SETEX "prediction:user:1001:fraud_score" 300 "0.15"
redis_cmd TTL "prediction:user:1001:fraud_score"

# Rate Limiting
echo -e "\nTesting Rate Limiting..."
redis_cmd SETEX "rate_limit:api:user:1001" 60 "1"
redis_cmd INCR "rate_limit:api:user:1001"
redis_cmd GET "rate_limit:api:user:1001"

# Session Management
echo -e "\nTesting Session Management..."
SESSION_DATA='{"user_id":"1001","token":"abc123","expires":"2024-01-16T00:00:00Z"}'
redis_cmd SETEX "session:abc123" 86400 "$SESSION_DATA"
redis_cmd GET "session:abc123"

# Leaderboard
echo -e "\nTesting Leaderboard..."
redis_cmd ZADD "leaderboard:model_accuracy" \
    95.5 "model_1" \
    97.2 "model_2" \
    96.8 "model_3"
redis_cmd ZREVRANGE "leaderboard:model_accuracy" 0 -1 WITHSCORES

echo -e "\n${BLUE}11. Testing Redis Modules (if available)${NC}"

# Check for RedisJSON
if redis_cmd MODULE LIST | grep -q ReJSON; then
    echo "Testing RedisJSON..."
    redis_cmd JSON.SET doc:1 '$' '{"name":"ML Platform","version":"1.0"}'
    redis_cmd JSON.GET doc:1
else
    echo "RedisJSON not loaded"
fi

# Check for RedisTimeSeries
if redis_cmd MODULE LIST | grep -q timeseries; then
    echo "Testing RedisTimeSeries..."
    redis_cmd TS.CREATE temperature:sensor1
    redis_cmd TS.ADD temperature:sensor1 "*" 25.5
    redis_cmd TS.GET temperature:sensor1
else
    echo "RedisTimeSeries not loaded"
fi

echo -e "\n${BLUE}12. Monitoring and Stats${NC}"
redis_cmd INFO stats | grep -E "total_commands_processed|instantaneous_ops_per_sec"
redis_cmd CLIENT LIST
redis_cmd CONFIG GET maxmemory

echo -e "\n${BLUE}13. Cleanup${NC}"
redis_cmd FLUSHDB

echo -e "\n${GREEN}=== All Redis Tests Completed ===${NC}"
REDIS_TEST_EOF

chmod +x test-redis-comprehensive.sh

# Create Redis monitoring dashboard script
cat > monitor-redis.sh << 'MONITOR_EOF'
#!/bin/bash

# Redis Monitoring Dashboard
clear

while true; do
    clear
    echo "=== Redis Real-Time Monitor ==="
    echo "Time: $(date)"
    echo ""
    
    # Basic Info
    echo "=== Server Info ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO server | grep -E "redis_version|uptime_in_seconds|process_id"
    
    echo -e "\n=== Clients ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO clients | grep -E "connected_clients|blocked_clients"
    
    echo -e "\n=== Memory ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO memory | grep -E "used_memory_human|used_memory_peak_human|mem_fragmentation_ratio"
    
    echo -e "\n=== Stats ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO stats | grep -E "total_commands_processed|instantaneous_ops_per_sec|total_net_input_bytes|total_net_output_bytes"
    
    echo -e "\n=== Replication ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO replication | grep -E "role|connected_slaves|master_repl_offset"
    
    echo -e "\n=== Keyspace ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO keyspace
    
    echo -e "\n=== Slow Queries ==="
    docker exec ml-redis-master redis-cli -a redispass123 SLOWLOG GET 5
    
    sleep 5
done
MONITOR_EOF

chmod +x monitor-redis.sh

# Create Redis inspection script
cat > inspect-redis.sh << 'INSPECT_EOF'
#!/bin/bash

echo "=== Redis Inspection Tool ==="

# Function to run Redis commands
redis_cmd() {
    docker exec ml-redis-master redis-cli -a redispass123 "$@"
}

# 1. Server Information
echo -e "\n1. Server Information:"
redis_cmd INFO server

# 2. Memory Analysis
echo -e "\n2. Memory Analysis:"
redis_cmd MEMORY STATS
redis_cmd MEMORY DOCTOR

# 3. Key Analysis
echo -e "\n3. Key Analysis:"
redis_cmd DBSIZE
redis_cmd SCAN 0 COUNT 10

# 4. Configuration
echo -e "\n4. Current Configuration:"
redis_cmd CONFIG GET "*" | head -20

# 5. Connected Clients
echo -e "\n5. Connected Clients:"
redis_cmd CLIENT LIST

# 6. Slow Log
echo -e "\n6. Recent Slow Queries:"
redis_cmd SLOWLOG GET 10

# 7. Latest Commands
echo -e "\n7. Monitor Commands (5 seconds):"
timeout 5 docker exec ml-redis-master redis-cli -a redispass123 MONITOR || true

# 8. Persistence Status
echo -e "\n8. Persistence Status:"
redis_cmd INFO persistence

# 9. Replication Status
echo -e "\n9. Replication Status:"
redis_cmd INFO replication

# 10. Keyspace Stats
echo -e "\n10. Keyspace Statistics:"
redis_cmd INFO keyspace

# 11. CPU Usage
echo -e "\n11. CPU Usage:"
redis_cmd INFO cpu

# 12. Command Stats
echo -e "\n12. Command Statistics:"
redis_cmd INFO commandstats | head -20

# 13. Latency Analysis
echo -e "\n13. Latency Analysis:"
redis_cmd LATENCY DOCTOR

# 14. Module List
echo -e "\n14. Loaded Modules:"
redis_cmd MODULE LIST

# 15. ACL Users
echo -e "\n15. ACL Users:" redis_cmd ACL LIST
INSPECT_EOF

chmod +x inspect-redis.sh

# Step 17: Create test scripts
echo -e "\n${BLUE}Step 17: Creating test scripts...${NC}"

cat > test-platform.sh << 'TEST_EOF'
#!/bin/bash

echo "Testing ML Platform Enterprise..."

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test Docker services
echo -e "\n1. Testing Docker services:"
docker-compose -f infrastructure/docker/docker-compose.yml ps
docker-compose -f infrastructure/docker/docker-compose-redis-enhanced.yml ps

# Test Kubernetes deployments
echo -e "\n2. Testing Kubernetes deployments:"
kubectl get all -n ml-platform
kubectl get all -n monitoring

# Test API endpoint
echo -e "\n3. Testing API endpoint:"
if curl -s http://localhost:8000/health | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}API is healthy${NC}"
    curl -s http://localhost:8000/health | jq .
else
    echo -e "${RED}API is not responding${NC}"
fi

# Test databases
echo -e "\n4. Testing databases:"

# PostgreSQL
if docker exec ml-postgres-primary psql -U mluser -d mlplatform -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}PostgreSQL is working${NC}"
else
    echo -e "${RED}PostgreSQL is not working${NC}"
fi

# Redis
if docker exec ml-redis-master redis-cli -a redispass123 ping | grep -q PONG; then
    echo -e "${GREEN}Redis is working${NC}"
else
    echo -e "${RED}Redis is not working${NC}"
fi

# MongoDB
if docker exec ml-mongodb mongosh -u admin -p mongopass123 --eval "db.version()" > /dev/null 2>&1; then
    echo -e "${GREEN}MongoDB is working${NC}"
else
    echo -e "${RED}MongoDB is not working${NC}"
fi

# Test monitoring
echo -e "\n5. Testing monitoring:"
if curl -s http://localhost:9090/api/v1/query?query=up | grep -q "success"; then
    echo -e "${GREEN}Prometheus is working${NC}"
else
    echo -e "${RED}Prometheus is not working${NC}"
fi

if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo -e "${GREEN}Grafana is working${NC}"
else
    echo -e "${RED}Grafana is not working${NC}"
fi

# Test Redis cluster
echo -e "\n6. Testing Redis cluster:"
echo "Master status:"
docker exec ml-redis-master redis-cli -a redispass123 INFO replication | grep role

echo "Replica 1 status:"
docker exec ml-redis-replica-1 redis-cli -a redispass123 INFO replication | grep -E "role|master_host"

echo "Replica 2 status:"
docker exec ml-redis-replica-2 redis-cli -a redispass123 INFO replication | grep -E "role|master_host"

echo -e "\nAll tests completed!"
TEST_EOF

chmod +x test-platform.sh

# Create complete workflow test
cat > test-ml-workflow.sh << 'WORKFLOW_EOF'
#!/bin/bash

echo "Testing complete ML workflow..."

# Register user
echo "1. Registering user..."
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "testpass123"
  }')

TOKEN=$(echo $REGISTER_RESPONSE | jq -r .access_token)
echo "Token received: ${TOKEN:0:20}..."

# Train model
echo -e "\n2. Training model..."
TRAIN_RESPONSE=$(curl -s -X POST http://localhost:8000/api/v1/models/train \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-model",
    "model_type": "classification",
    "dataset_id": "test-dataset",
    "parameters": {"n_estimators": 100}
  }')

MODEL_ID=$(echo $TRAIN_RESPONSE | jq -r .model_id)
echo "Model ID: $MODEL_ID"

# Get model status
echo -e "\n3. Checking model status..."
sleep 2
curl -s -X GET http://localhost:8000/api/v1/models/$MODEL_ID \
  -H "Authorization: Bearer $TOKEN" | jq .

# Make prediction
echo -e "\n4. Making prediction..."
PREDICTION_RESPONSE=$(curl -s -X POST http://localhost:8000/api/v1/models/$MODEL_ID/predict \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": [[1.0, 2.0, 3.0, 4.0], [5.0, 6.0, 7.0, 8.0]]
  }')

echo "Predictions: $(echo $PREDICTION_RESPONSE | jq .predictions)"

# Store features
echo -e "\n5. Storing features..."
curl -s -X POST http://localhost:8000/api/v1/features/store \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "feature_set": "user_features",
    "features": {
      "age": "25",
      "location": "NYC",
      "purchase_count": "42"
    }
  }' | jq .

# Get features
echo -e "\n6. Retrieving features..."
curl -s -X GET http://localhost:8000/api/v1/features/user_features \
  -H "Authorization: Bearer $TOKEN" | jq .

# List models
echo -e "\n7. Listing all models..."
curl -s -X GET http://localhost:8000/api/v1/models \
  -H "Authorization: Bearer $TOKEN" | jq .

# Check Redis cache
echo -e "\n8. Checking Redis cache..."
docker exec ml-redis-master redis-cli -a redispass123 KEYS "*" | head -10

echo -e "\nWorkflow test completed!"
WORKFLOW_EOF

chmod +x test-ml-workflow.sh

# Step 18: Display access information
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}   ML Platform Enterprise Setup Complete!${NC}"
echo -e "${GREEN}   Running Locally with Full Complexity${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Access Points:"
echo "-------------"
echo "Kubernetes Dashboard:  minikube dashboard"
echo "ML Platform API:       http://localhost:8000"
echo "API Documentation:     http://localhost:8000/docs"
echo "Prometheus:           http://localhost:9090"
echo "Grafana:              http://localhost:3000 (admin/admin)"
echo "MinIO Console:        http://localhost:9001 (minioadmin/minioadmin123)"
echo "PostgreSQL:           localhost:5432 (mluser/mlpass123)"
echo "MongoDB:              localhost:27017 (admin/mongopass123)"
echo "Kafka:                localhost:9092"
echo "Vault:                http://localhost:8200 (Token: myroot)"
echo "Container Registry:   localhost:32770"
echo ""
echo "Redis Access:"
echo "-------------"
echo "Redis Master:         localhost:6379 (password: redispass123)"
echo "Redis Replica 1:      localhost:6380 (password: redispass123)"
echo "Redis Replica 2:      localhost:6381 (password: redispass123)"
echo "Redis Sentinel:       localhost:26379"
echo "RedisInsight GUI:     http://localhost:8001"
echo "Redis Exporter:       http://localhost:9121/metrics"
echo ""
echo "Test Commands:"
echo "--------------"
echo "Basic tests:          ./test-platform.sh"
echo "ML workflow test:     ./test-ml-workflow.sh"
echo "Redis tests:          ./test-redis-comprehensive.sh"
echo "Monitor Redis:        ./monitor-redis.sh"
echo "Inspect Redis:        ./inspect-redis.sh"
echo ""
echo "Useful Commands:"
echo "----------------"
echo "View all pods:        kubectl get pods -A"
echo "View ML logs:         kubectl logs -n ml-platform -l app=ml-platform-api"
echo "View all services:    docker-compose -f infrastructure/docker/docker-compose.yml ps"
echo "Connect to Redis:     docker exec -it ml-redis-master redis-cli -a redispass123"
echo ""
echo "Monitoring:"
echo "-----------"
echo "Kubernetes metrics:   kubectl top nodes && kubectl top pods -A"
echo "Docker stats:         docker stats"
echo "API metrics:          curl http://localhost:8000/metrics"
echo ""
echo "Stop Everything:"
echo "----------------"
echo "docker-compose -f infrastructure/docker/docker-compose.yml down"
echo "docker-compose -f infrastructure/docker/docker-compose-redis-enhanced.yml down"
echo "minikube stop"
echo ""
echo "Everything is running locally!"
echo ""
echo "Note: If you see connection errors, wait a minute for all services to fully start,"
echo "then run: ./test-platform.sh"

# Run initial tests
echo -e "\n${BLUE}Running initial tests...${NC}"
sleep 10
./test-redis-comprehensive.sh

