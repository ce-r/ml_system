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
    echo -e "${GREEN}✓ Redis is responding${NC}"
else
    echo -e "${RED}✗ Redis is not responding${NC}"
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
