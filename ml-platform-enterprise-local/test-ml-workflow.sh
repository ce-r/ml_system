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
