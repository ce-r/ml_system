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

    class Config:
        protected_namespaces = ()

class TrainingRequest(BaseModel):
    model_name: str
    dataset_path: str
    epochs: int = 10

    class Config: # not a redefinition, Config is a special pydantic nested class used to configure 
                  # behavior of outer model. By default, Pydantic protects field names like model_, schema_, etc
        protected_namespaces = ()

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
