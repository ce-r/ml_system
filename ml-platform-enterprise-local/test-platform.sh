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
    echo -e "${GREEN}✓ API is healthy${NC}"
    curl -s http://localhost:8000/health | jq .
else
    echo -e "${RED}✗ API is not responding${NC}"
fi

# Test databases
echo -e "\n4. Testing databases:"

# PostgreSQL
if docker exec ml-postgres-primary psql -U mluser -d mlplatform -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL is working${NC}"
else
    echo -e "${RED}✗ PostgreSQL is not working${NC}"
fi

# Redis
if docker exec ml-redis-master redis-cli -a redispass123 ping | grep -q PONG; then
    echo -e "${GREEN}✓ Redis is working${NC}"
else
    echo -e "${RED}✗ Redis is not working${NC}"
fi

# MongoDB
if docker exec ml-mongodb mongosh -u admin -p mongopass123 --eval "db.version()" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ MongoDB is working${NC}"
else
    echo -e "${RED}✗ MongoDB is not working${NC}"
fi

# Test monitoring
echo -e "\n5. Testing monitoring:"
if curl -s http://localhost:9090/api/v1/query?query=up | grep -q "success"; then
    echo -e "${GREEN}✓ Prometheus is working${NC}"
else
    echo -e "${RED}✗ Prometheus is not working${NC}"
fi

if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo -e "${GREEN}✓ Grafana is working${NC}"
else
    echo -e "${RED}✗ Grafana is not working${NC}"
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
