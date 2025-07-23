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
