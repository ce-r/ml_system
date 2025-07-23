#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== ML Platform Health Check ===${NC}\n"

# Check Docker containers
echo -e "${YELLOW}Docker Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "ml-|NAME"

echo -e "\n${YELLOW}Service Status:${NC}"

# PostgreSQL
echo -n "PostgreSQL: "
docker exec ml-postgres-primary pg_isready -U mluser -d mlplatform &>/dev/null && echo -e "${GREEN}✓ HEALTHY${NC}" || echo -e "${RED}✗ UNHEALTHY${NC}"

# Redis
echo -n "Redis Master: "
docker exec ml-redis-master redis-cli -a redispass123 ping 2>/dev/null | grep -q PONG && echo -e "${GREEN}✓ HEALTHY${NC}" || echo -e "${RED}✗ UNHEALTHY${NC}"

# MongoDB
echo -n "MongoDB: "
docker exec ml-mongodb mongosh -u admin -p mongopass123 --authenticationDatabase admin --eval "db.adminCommand('ping')" 2>/dev/null | grep -q "ok: 1" && echo -e "${GREEN}✓ HEALTHY${NC}" || echo -e "${RED}✗ UNHEALTHY${NC}"

# MinIO
echo -n "MinIO: "
curl -s http://localhost:9000/minio/health/live &>/dev/null && echo -e "${GREEN}✓ HEALTHY${NC}" || echo -e "${RED}✗ UNHEALTHY${NC}"

# API
echo -n "API: "
curl -s http://localhost:8000/health &>/dev/null && echo -e "${GREEN}✓ HEALTHY${NC}" || echo -e "${RED}✗ UNHEALTHY${NC}"

echo -e "\n${YELLOW}API Health Response:${NC}"
curl -s http://localhost:8000/health | jq '.' 2>/dev/null || echo "API not responding"

echo -e "\n${YELLOW}MongoDB Collections:${NC}"
docker exec ml-mongodb mongosh -u admin -p mongopass123 --authenticationDatabase admin --eval "use mlplatform; db.getCollectionNames()" 2>/dev/null | grep -v "Using MongoDB" | grep -v "MongoSH" || echo "Cannot connect to MongoDB"