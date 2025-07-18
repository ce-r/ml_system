"""
Simplified ML Platform for Local Development
All services in one for easy student use
"""

from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Dict, List, Optional, Any
import numpy as np
from datetime import datetime
import json
import logging
import time
import random
import os
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import psutil

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="ML Platform (Local)",
    description="Free ML Platform for Students",
    version="1.0.0"
)

# Prometheus metrics
REQUEST_COUNT = Counter('app_requests_total', 'Total app requests', ['method', 'endpoint'])
REQUEST_LATENCY = Histogram('app_request_duration_seconds', 'Request latency')
PREDICTION_COUNT = Counter('predictions_total', 'Total predictions made')
MODEL_TRAINING_COUNT = Counter('model_training_total', 'Total model training jobs')

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

# Create directories
os.makedirs(config.MODEL_PATH, exist_ok=True)
os.makedirs(config.DATA_PATH, exist_ok=True)

# Security
security = HTTPBearer()

# Mock databases (since we're running without external deps for now)
users_db = {
    "student1": {"password": "pass123", "id": 1, "role": "student"},
    "admin": {"password": "admin123", "id": 2, "role": "admin"}
}

models_db = {}
datasets_db = {}

# Simple ML model class (mock)
class SimpleMLModel:
    def __init__(self, input_size=10, hidden_size=20, output_size=1):
        self.input_size = input_size
        self.hidden_size = hidden_size
        self.output_size = output_size
        self.weights = np.random.randn(input_size, output_size)
        self.bias = np.random.randn(output_size)
        
    def forward(self, x):
        # Simple linear transformation
        return np.dot(x, self.weights) + self.bias
    
    def train(self, X, y, epochs=100):
        # Mock training - just simulate
        for epoch in range(epochs):
            time.sleep(0.01)  # Simulate training time
            if epoch % 20 == 0:
                logger.info(f"Training epoch {epoch}/{epochs}")
    
    def save(self, path):
        np.savez(path, weights=self.weights, bias=self.bias)
    
    def load(self, path):
        data = np.load(path)
        self.weights = data['weights']
        self.bias = data['bias']

# Data models
class UserModel(BaseModel):
    username: str
    password: str
    role: str = "student"

class LoginRequest(BaseModel):
    username: str
    password: str

class DatasetUpload(BaseModel):
    name: str
    description: str
    data: List[Dict[str, Any]]

class ModelRequest(BaseModel):
    name: str
    model_type: str = "linear"
    parameters: Dict[str, Any] = {}

class TrainingRequest(BaseModel):
    model_name: str
    dataset_name: str
    epochs: int = 100
    learning_rate: float = 0.01

class PredictionRequest(BaseModel):
    model_name: str
    inputs: List[float]

# Middleware for metrics
@app.middleware("http")
async def metrics_middleware(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    
    REQUEST_COUNT.labels(method=request.method, endpoint=request.url.path).inc()
    REQUEST_LATENCY.observe(process_time)
    
    return response

# Helper functions
def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    # Simple token verification (for learning purposes)
    token = credentials.credentials
    if token in ["student-token", "admin-token"]:
        return {"username": "student1" if token == "student-token" else "admin"}
    raise HTTPException(status_code=401, detail="Invalid token")

# Routes
@app.get("/")
async def root():
    return {
        "message": "Welcome to ML Platform (Local)",
        "version": "1.0.0",
        "services": ["models", "datasets", "training", "predictions"],
        "status": "running"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "uptime": time.time(),
        "memory_usage": psutil.virtual_memory().percent,
        "cpu_usage": psutil.cpu_percent()
    }

@app.post("/auth/register")
async def register(user: UserModel):
    if user.username in users_db:
        raise HTTPException(status_code=400, detail="User already exists")
    
    users_db[user.username] = {
        "password": user.password,
        "id": len(users_db) + 1,
        "role": user.role
    }
    
    logger.info(f"User {user.username} registered")
    return {"message": "User registered successfully", "user_id": users_db[user.username]["id"]}

@app.post("/auth/login")
async def login(request: LoginRequest):
    if request.username not in users_db:
        raise HTTPException(status_code=401, detail="User not found")
    
    user = users_db[request.username]
    if user["password"] != request.password:
        raise HTTPException(status_code=401, detail="Invalid password")
    
    # Return simple token for demo
    token = f"{user['role']}-token"
    logger.info(f"User {request.username} logged in")
    return {"access_token": token, "token_type": "bearer", "user_id": user["id"]}

@app.post("/datasets/upload")
async def upload_dataset(dataset: DatasetUpload, user: dict = Depends(verify_token)):
    dataset_id = f"dataset_{len(datasets_db) + 1}"
    
    datasets_db[dataset.name] = {
        "id": dataset_id,
        "name": dataset.name,
        "description": dataset.description,
        "data": dataset.data,
        "created_at": datetime.now().isoformat(),
        "created_by": user["username"],
        "size": len(dataset.data)
    }
    
    # Save to file
    dataset_path = os.path.join(config.DATA_PATH, f"{dataset.name}.json")
    with open(dataset_path, 'w') as f:
        json.dump(dataset.data, f)
    
    logger.info(f"Dataset {dataset.name} uploaded by {user['username']}")
    return {"message": "Dataset uploaded successfully", "dataset_id": dataset_id}

@app.get("/datasets")
async def list_datasets(user: dict = Depends(verify_token)):
    return {"datasets": list(datasets_db.values())}

@app.post("/models/create")
async def create_model(request: ModelRequest, user: dict = Depends(verify_token)):
    model_id = f"model_{len(models_db) + 1}"
    
    # Create simple model
    model = SimpleMLModel()
    model_path = os.path.join(config.MODEL_PATH, f"{request.name}.npz")
    model.save(model_path)
    
    models_db[request.name] = {
        "id": model_id,
        "name": request.name,
        "type": request.model_type,
        "parameters": request.parameters,
        "path": model_path,
        "created_at": datetime.now().isoformat(),
        "created_by": user["username"],
        "status": "created"
    }
    
    logger.info(f"Model {request.name} created by {user['username']}")
    return {"message": "Model created successfully", "model_id": model_id}

@app.get("/models")
async def list_models(user: dict = Depends(verify_token)):
    return {"models": list(models_db.values())}

@app.post("/training/start")
async def start_training(request: TrainingRequest, user: dict = Depends(verify_token)):
    if request.model_name not in models_db:
        raise HTTPException(status_code=404, detail="Model not found")
    
    if request.dataset_name not in datasets_db:
        raise HTTPException(status_code=404, detail="Dataset not found")
    
    # Simulate training
    model = SimpleMLModel()
    model.load(models_db[request.model_name]["path"])
    
    # Mock training data
    X = np.random.randn(1000, 10)
    y = np.random.randint(0, 2, (1000, 1)).float()
    
    logger.info(f"Starting training for model {request.model_name}")
    model.train(X, y, epochs=request.epochs)
    
    # Save trained model
    model_path = models_db[request.model_name]["path"]
    model.save(model_path)
    
    models_db[request.model_name]["status"] = "trained"
    models_db[request.model_name]["last_trained"] = datetime.now().isoformat()
    
    MODEL_TRAINING_COUNT.inc()
    logger.info(f"Training completed for model {request.model_name}")
    
    return {
        "message": "Training completed successfully",
        "model_name": request.model_name,
        "epochs": request.epochs,
        "status": "trained"
    }

@app.post("/predict")
async def predict(request: PredictionRequest, user: dict = Depends(verify_token)):
    if request.model_name not in models_db:
        raise HTTPException(status_code=404, detail="Model not found")
    
    model_info = models_db[request.model_name]
    if model_info["status"] != "trained":
        raise HTTPException(status_code=400, detail="Model not trained yet")
    
    # Load model and make prediction
    model = SimpleMLModel()
    model.load(model_info["path"])
    
    input_array = np.array(request.inputs)
    if len(input_array.shape) == 1:
        input_array = input_array.reshape(1, -1)
    
    prediction = model.forward(input_array)
    
    PREDICTION_COUNT.inc()
    logger.info(f"Prediction made with model {request.model_name}")
    
    return {
        "model_name": request.model_name,
        "inputs": request.inputs,
        "prediction": prediction.tolist(),
        "timestamp": datetime.now().isoformat()
    }

@app.get("/monitoring/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/monitoring/stats")
async def get_stats(user: dict = Depends(verify_token)):
    """System statistics"""
    return {
        "system": {
            "cpu_percent": psutil.cpu_percent(),
            "memory": {
                "total": psutil.virtual_memory().total,
                "available": psutil.virtual_memory().available,
                "percent": psutil.virtual_memory().percent
            },
            "disk": {
                "total": psutil.disk_usage('/').total,
                "free": psutil.disk_usage('/').free,
                "percent": psutil.disk_usage('/').percent
            }
        },
        "application": {
            "total_users": len(users_db),
            "total_models": len(models_db),
            "total_datasets": len(datasets_db),
            "uptime": time.time()
        }
    }

if __name__ == "__main__":
    import uvicorn
    logger.info("Starting ML Platform (Local)")
    uvicorn.run(app, host="0.0.0.0", port=8000)
