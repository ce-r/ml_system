#!/bin/bash

echo "=== MongoDB Connection Debug ==="

# 1. Check MongoDB container networking
echo -e "\n1. MongoDB Container Network:"
docker inspect ml-mongodb | jq '.[0].NetworkSettings.Networks' 2>/dev/null

# 2. Test MongoDB auth directly
echo -e "\n2. Direct MongoDB Auth Test:"
docker exec ml-mongodb mongosh -u admin -p mongopass123 --authenticationDatabase admin --eval "db.adminCommand('ping')"

# 3. Check if mlplatform database exists
echo -e "\n3. Database List:"
docker exec ml-mongodb mongosh -u admin -p mongopass123 --authenticationDatabase admin --eval "show dbs"

# 4. Check collections in mlplatform
echo -e "\n4. Collections in mlplatform:"
docker exec ml-mongodb mongosh -u admin -p mongopass123 --authenticationDatabase admin --eval "use mlplatform; db.getCollectionNames()"

# 5. Check API container logs for MongoDB errors
echo -e "\n5. API Container Logs (MongoDB related):"
docker ps | grep -E "api|8000" | awk '{print $1}' | xargs -I {} docker logs {} 2>&1 | grep -i "mongo" | tail -10

# 6. Test MongoDB connection from API container
echo -e "\n6. Testing MongoDB from API container:"
API_CONTAINER=$(docker ps | grep -E "api|8000" | awk '{print $1}' | head -1)
if [ ! -z "$API_CONTAINER" ]; then
    docker exec $API_CONTAINER python -c "
import motor.motor_asyncio
import asyncio

async def test():
    try:
        client = motor.motor_asyncio.AsyncIOMotorClient('mongodb://admin:mongopass123@ml-mongodb:27017/mlplatform?authSource=admin')
        result = await client.admin.command('ping')
        print('MongoDB connection from API: SUCCESS')
        print(f'Result: {result}')
    except Exception as e:
        print(f'MongoDB connection from API: FAILED - {e}')

asyncio.run(test())
"
else
    echo "No API container found running"
fi

# 7. Check if API is running locally or in container
echo -e "\n7. API Process Check:"
ps aux | grep -E "uvicorn|fastapi|app.py" | grep -v grep

# 8. Network connectivity test
echo -e "\n8. Network Test (MongoDB port):"
nc -zv localhost 27017
