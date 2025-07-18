#!/bin/bash

echo "Starting ML Platform Local..."

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
# python3 -m venv venv
# source venv/bin/activate
# pip install -r requirements.txt

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
