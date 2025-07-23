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
