
#!/bin/bash

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   ML Platform Local Setup ${NC}"
echo -e "${BLUE}================================================${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service
wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=1
   
    echo -e "${YELLOW}Waiting for $service to be ready...${NC}"
    while ! nc -z localhost $port; do
        if [ $attempt -eq $max_attempts ]; then
            echo -e "${RED}$service failed to start${NC}"
            return 1
        fi
        sleep 2
        ((attempt++))
    done
    echo -e "${GREEN}✓ $service is ready${NC}"
}

# Step 1: Check and install prerequisites
echo -e "\n${BLUE}Step 1: Checking prerequisites...${NC}"

MISSING_TOOLS=()

# Check required tools
for tool in docker docker-compose python3 git curl; do
    if ! command_exists $tool; then
        MISSING_TOOLS+=($tool)
        echo -e "${RED}✗ $tool not found${NC}"
    else
        echo -e "${GREEN}✓ $tool installed${NC}"
    fi
done

# Install missing tools
if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "\n${YELLOW}Installing missing tools...${NC}"
   
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        sudo apt-get update
       
        # Install Docker
        if [[ " ${MISSING_TOOLS[@]} " =~ " docker " ]]; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            echo -e "${YELLOW}Please log out and back in for Docker permissions${NC}"
        fi
       
        # Install Docker Compose
        if [[ " ${MISSING_TOOLS[@]} " =~ " docker-compose " ]]; then
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
       
        # Install Python 3
        if [[ " ${MISSING_TOOLS[@]} " =~ " python3 " ]]; then
            sudo apt-get install -y python3 python3-pip python3-venv
        fi
       
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command_exists brew; then
            echo "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
       
        for tool in "${MISSING_TOOLS[@]}"; do
            brew install $tool
        done
    fi
fi

# Step 2: Create project structure
echo -e "\n${BLUE}Step 2: Creating project structure...${NC}"

PROJECT_DIR="$HOME/ml-platform-local"
mkdir -p $PROJECT_DIR/{services,data,models,configs,secrets,logs}
cd $PROJECT_DIR

# Step 3: Create all service files
echo -e "\n${BLUE}Step 3: Creating service files...${NC}"

# Create docker-compose.yml for all services
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  # Databases
  postgres:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: mlplatform
      POSTGRES_PASSWORD: localpass123
      POSTGRES_DB: mlplatform
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mlplatform"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  mongodb:
    image: mongo:5
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: localpass123
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db

  # Message Queue
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    volumes:
      - zookeeper_data:/var/lib/zookeeper/data

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
    volumes:
      - kafka_data:/var/lib/kafka/data

  # Object Storage S3 replacement
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # Monitoring
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./configs/grafana-dashboards:/etc/grafana/provisioning/dashboards

  # Jupyter for experimentation
  jupyter:
    image: jupyter/tensorflow-notebook:latest
    ports:
      - "8888:8888"
    environment:
      JUPYTER_ENABLE_LAB: "yes"
    volumes:
      - ./notebooks:/home/jovyan/work
      - ./data:/home/jovyan/data
      - ./models:/home/jovyan/models
    command: start-notebook.sh --NotebookApp.token='' --NotebookApp.password=''

volumes:
  postgres_data:
  redis_data:
  mongo_data:
  zookeeper_data:
  kafka_data:
  minio_data:
  prometheus_data:
  grafana_data:
EOF

# Create Prometheus config
mkdir -p configs
cat > configs/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'ml-platform'
    static_configs:
      - targets: ['host.docker.internal:8000', 'host.docker.internal:8001', 'host.docker.internal:8002']
EOF

# Step 4: Create simplified ML services
echo -e "\n${BLUE}Step 4: Creating ML services...${NC}"

# Create a simple all-in-one ML service for local development
mkdir -p services/ml-platform

cat > services/ml-platform/app.py <<'EOF'
"""
Simplified ML Platform for Local Development
All services in one for easy student use
"""

from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Dict, List, Optional, Any
import pandas as pd
import numpy as np
import torch
import torch.nn as nn
from datetime import datetime
import redis
import asyncpg
import motor.motor_asyncio
import jwt
import json
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="ML Platform (Local)",
    description="Free ML Platform for Students",
    version="1.0.0"
)

# Configuration (all local, no cloud services)
class Config:
    # Local services only
    POSTGRES_URL = "postgresql://mlplatform:localpass123@localhost:5432/mlplatform"
    REDIS_URL = "redis://localhost:6379"
    MONGODB_URL = "mongodb://admin:localpass123@localhost:27017"
   
    # Local storage
    MODEL_PATH = "./models"
    DATA_PATH = "./data"
   
    # Simple auth (for learning)
    JWT_SECRET = "local-secret-key"
    JWT_ALGORITHM = "HS256"

config = Config()

# Security
security = HTTPBearer()

# Simple models for demonstration
class UserCreate(BaseModel):
    username: str
    password: str
    email: str

class FeatureData(BaseModel):
    entity_id: str
    features: Dict[str, float]

class PredictionRequest(BaseModel):
    model_name: str
    features: Dict[str, float]

class TrainingRequest(BaseModel):
    model_name: str
    dataset_path: str
    epochs: int = 10

# Simple PyTorch model for demonstration
class SimpleModel(nn.Module):
    def __init__(self, input_size=10, hidden_size=64, output_size=1):
        super().__init__()
        self.fc1 = nn.Linear(input_size, hidden_size)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(hidden_size, output_size)
        self.sigmoid = nn.Sigmoid()
   
    def forward(self, x):
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        x = self.sigmoid(x)
        return x

# In-memory storage for demo (in production, use databases)
users_db = {}
models_db = {}
features_db = {}

# Helper functions
def create_token(user_id: str) -> str:
    """Create JWT token"""
    payload = {
        "user_id": user_id,
        "exp": datetime.utcnow().timestamp() + 86400  # 24 hours
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify JWT token"""
    token = credentials.credentials
    try:
        payload = jwt.decode(token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return payload["user_id"]
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

# Endpoints
@app.get("/")
async def root():
    """Welcome endpoint"""
    return {
        "message": "Welcome to ML Platform (Local Edition)",
        "docs": "/docs",
        "features": [
            "User Authentication",
            "Feature Store",
            "Model Training",
            "Model Serving",
            "Real-time Predictions"
        ],
        "cost": "$0 - Everything runs locally!"
    }

@app.get("/health")
async def health_check():
    """Health check"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "services": {
            "api": "running",
            "database": "local",
            "redis": "local",
            "storage": "local filesystem"
        }
    }

# Authentication endpoints
@app.post("/auth/register")
async def register(user: UserCreate):
    """Register new user"""
    if user.username in users_db:
        raise HTTPException(status_code=400, detail="User already exists")
   
    # Simple password hashing (use bcrypt in production)
    users_db[user.username] = {
        "password": user.password,  # Don't do this in production!
        "email": user.email,
        "created_at": datetime.utcnow().isoformat()
    }
   
    return {"message": "User created successfully", "username": user.username}

@app.post("/auth/login")
async def login(username: str, password: str):
    """Login user"""
    if username not in users_db or users_db[username]["password"] != password:
        raise HTTPException(status_code=401, detail="Invalid credentials")
   
    token = create_token(username)
    return {"access_token": token, "token_type": "bearer"}

# Feature Store endpoints
@app.post("/features/store")
async def store_features(data: FeatureData, user_id: str = Depends(get_current_user)):
    """Store features"""
    if data.entity_id not in features_db:
        features_db[data.entity_id] = {}
   
    features_db[data.entity_id].update(data.features)
    features_db[data.entity_id]["updated_at"] = datetime.utcnow().isoformat()
   
    return {"message": "Features stored successfully", "entity_id": data.entity_id}

@app.get("/features/{entity_id}")
async def get_features(entity_id: str, user_id: str = Depends(get_current_user)):
    """Get features for entity"""
    if entity_id not in features_db:
        raise HTTPException(status_code=404, detail="Entity not found")
   
    return features_db[entity_id]

# Model Training endpoints
@app.post("/models/train")
async def train_model(request: TrainingRequest, user_id: str = Depends(get_current_user)):
    """Train a simple model"""
    try:
        # Create simple model
        model = SimpleModel()
       
        # Generate dummy training data
        X = torch.randn(1000, 10)
        y = torch.randint(0, 2, (1000, 1)).float()
       
        # Simple training loop
        optimizer = torch.optim.Adam(model.parameters())
        criterion = nn.BCELoss()
       
        for epoch in range(request.epochs):
            optimizer.zero_grad()
            outputs = model(X)
            loss = criterion(outputs, y)
            loss.backward()
            optimizer.step()
       
        # Save model
        model_path = f"{config.MODEL_PATH}/{request.model_name}.pth"
        torch.save(model.state_dict(), model_path)
       
        # Store model metadata
        models_db[request.model_name] = {
            "path": model_path,
            "trained_by": user_id,
            "trained_at": datetime.utcnow().isoformat(),
            "epochs": request.epochs,
            "status": "ready"
        }
       
        return {
            "message": "Model trained successfully",
            "model_name": request.model_name,
            "final_loss": float(loss.item())
        }
       
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/models")
async def list_models(user_id: str = Depends(get_current_user)):
    """List available models"""
    return {
        "models": [
            {
                "name": name,
                "status": info["status"],
                "trained_at": info["trained_at"]
            }
            for name, info in models_db.items()
        ]
    }

# Prediction endpoints
@app.post("/predict")
async def predict(request: PredictionRequest, user_id: str = Depends(get_current_user)):
    """Make prediction"""
    if request.model_name not in models_db:
        raise HTTPException(status_code=404, detail="Model not found")
   
    try:
        # Load model
        model = SimpleModel()
        model.load_state_dict(torch.load(models_db[request.model_name]["path"]))
        model.eval()
       
        # Prepare input
        input_values = list(request.features.values())
        input_tensor = torch.tensor(input_values).float().unsqueeze(0)
       
        # Make prediction
        with torch.no_grad():
            output = model(input_tensor)
            prediction = output.item()
       
        return {
            "model_name": request.model_name,
            "prediction": prediction,
            "probability": prediction,
            "timestamp": datetime.utcnow().isoformat()
        }
       
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# WebSocket for real-time features (simplified)
from fastapi import WebSocket

@app.websocket("/ws/features/{entity_id}")
async def websocket_features(websocket: WebSocket, entity_id: str):
    """WebSocket for real-time feature updates"""
    await websocket.accept()
    try:
        while True:
            # Send current features
            if entity_id in features_db:
                await websocket.send_json({
                    "entity_id": entity_id,
                    "features": features_db[entity_id],
                    "timestamp": datetime.utcnow().isoformat()
                })
           
            # Wait for updates (simplified - in production use pub/sub)
            await asyncio.sleep(5)
           
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        await websocket.close()

# A/B Testing (simplified)
@app.post("/experiments/create")
async def create_experiment(
    name: str,
    model_a: str,
    model_b: str,
    split: float = 0.5,
    user_id: str = Depends(get_current_user)
):
    """Create A/B test"""
    return {
        "experiment_id": f"exp_{name}",
        "model_a": model_a,
        "model_b": model_b,
        "traffic_split": split,
        "status": "active"
    }

if __name__ == "__main__":
    import uvicorn
    import os
   
    # Create directories
    os.makedirs(config.MODEL_PATH, exist_ok=True)
    os.makedirs(config.DATA_PATH, exist_ok=True)
   
    # Run server
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
EOF

# Create requirements.txt
cat > services/ml-platform/requirements.txt <<'EOF'
fastapi==0.104.1
uvicorn==0.24.0
pandas==2.1.3
numpy==1.24.3
torch==2.1.1
scikit-learn==1.3.2
redis==5.0.1
asyncpg==0.29.0
motor==3.3.2
pydantic==2.5.0
python-multipart==0.0.6
PyJWT==2.8.0
httpx==0.25.2
websockets==12.0
prometheus-client==0.19.0
EOF

# Create Dockerfile for ML service
cat > services/ml-platform/Dockerfile <<'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["python", "app.py"]
EOF

# Step 5: Create startup script
echo -e "\n${BLUE}Step 5: Creating startup script...${NC}"

cat > start-local.sh <<'EOF'
#!/bin/bash

echo "Starting ML Platform (Local)..."

# Start infrastructure
echo "Starting infrastructure services..."
docker-compose up -d postgres redis mongodb kafka minio

# Wait for services
sleep 30

# Initialize MinIO buckets
echo "Creating storage buckets..."
docker run --rm --network host minio/mc alias set myminio http://localhost:9000 minioadmin minioadmin123
docker run --rm --network host minio/mc mb myminio/models || true
docker run --rm --network host minio/mc mb myminio/features || true
docker run --rm --network host minio/mc mb myminio/data || true

# Start monitoring
echo "Starting monitoring services..."
docker-compose up -d prometheus grafana

# Start Jupyter
echo "Starting Jupyter notebook..."
docker-compose up -d jupyter

# Install Python dependencies locally
echo "Setting up Python environment..."
cd services/ml-platform
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Start ML service
echo "Starting ML service..."
python app.py &

echo "
ML Platform is running!

Access Points:
- API: http://localhost:8000
- API Docs: http://localhost:8000/docs
- Jupyter: http://localhost:8888 (no password)
- MinIO: http://localhost:9001 (minioadmin/minioadmin123)
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090

Quick Start:
1. Open API Docs: http://localhost:8000/docs
2. Register a user
3. Train a model
4. Make predictions

Cost: $0 - Everything is running locally!

To stop: docker-compose down
"
EOF

chmod +x start-local.sh

# Step 6: Create example notebook
echo -e "\n${BLUE}Step 6: Creating example notebook...${NC}"

mkdir -p notebooks
cat > notebooks/ml-platform-tutorial.ipynb <<'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# ML Platform Tutorial (Local)\n",
    "Welcome to your free ML Platform!"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import requests\n",
    "import json\n",
    "import pandas as pd\n",
    "import numpy as np\n",
    "\n",
    "# API base URL\n",
    "BASE_URL = \"http://localhost:8000\"\n",
    "\n",
    "# Check if platform is running\n",
    "response = requests.get(f\"{BASE_URL}/health\")\n",
    "print(\"Platform Status:\", response.json())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Register a user\n",
    "user_data = {\n",
    "    \"username\": \"student\",\n",
    "    \"password\": \"student123\",\n",
    "    \"email\": \"student@university.edu\"\n",
    "}\n",
    "\n",
    "response = requests.post(f\"{BASE_URL}/auth/register\", json=user_data)\n",
    "print(\"Registration:\", response.json())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Login\n",
    "login_response = requests.post(\n",
    "    f\"{BASE_URL}/auth/login\",\n",
    "    params={\"username\": \"student\", \"password\": \"student123\"}\n",
    ")\n",
    "token = login_response.json()[\"access_token\"]\n",
    "headers = {\"Authorization\": f\"Bearer {token}\"}\n",
    "print(\"Logged in successfully!\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Train a model\n",
    "training_request = {\n",
    "    \"model_name\": \"my_first_model\",\n",
    "    \"dataset_path\": \"dummy\",\n",
    "    \"epochs\": 5\n",
    "}\n",
    "\n",
    "response = requests.post(\n",
    "    f\"{BASE_URL}/models/train\",\n",
    "    json=training_request,\n",
    "    headers=headers\n",
    ")\n",
    "print(\"Training Result:\", response.json())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Make a prediction\n",
    "prediction_request = {\n",
    "    \"model_name\": \"my_first_model\",\n",
    "    \"features\": {\n",
    "        \"feature1\": 0.5,\n",
    "        \"feature2\": 1.2,\n",
    "        \"feature3\": -0.3,\n",
    "        \"feature4\": 2.1,\n",
    "        \"feature5\": 0.8\n",
    "    }\n",
    "}\n",
    "\n",
    "response = requests.post(\n",
    "    f\"{BASE_URL}/predict\",\n",
    "    json=prediction_request,\n",
    "    headers=headers\n",
    ")\n",
    "print(\"Prediction:\", response.json())"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

# Step 7: Run everything
echo -e "\n${BLUE}Step 7: Starting ML Platform...${NC}"

# Make script executable
chmod +x start-local.sh

# Start the platform
./start-local.sh

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}   ML Platform Setup Complete!${NC}"
echo -e "${GREEN}   Total Cost: \$0${NC}"
echo -e "${GREEN}================================================${NC}"


