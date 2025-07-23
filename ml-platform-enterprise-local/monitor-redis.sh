#!/bin/bash

# Redis Monitoring Dashboard
clear

while true; do
    clear
    echo "=== Redis Real-Time Monitor ==="
    echo "Time: $(date)"
    echo ""
    
    # Basic Info
    echo "=== Server Info ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO server | grep -E "redis_version|uptime_in_seconds|process_id"
    
    echo -e "\n=== Clients ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO clients | grep -E "connected_clients|blocked_clients"
    
    echo -e "\n=== Memory ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO memory | grep -E "used_memory_human|used_memory_peak_human|mem_fragmentation_ratio"
    
    echo -e "\n=== Stats ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO stats | grep -E "total_commands_processed|instantaneous_ops_per_sec|total_net_input_bytes|total_net_output_bytes"
    
    echo -e "\n=== Replication ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO replication | grep -E "role|connected_slaves|master_repl_offset"
    
    echo -e "\n=== Keyspace ==="
    docker exec ml-redis-master redis-cli -a redispass123 INFO keyspace
    
    echo -e "\n=== Slow Queries ==="
    docker exec ml-redis-master redis-cli -a redispass123 SLOWLOG GET 5
    
    sleep 5
done
