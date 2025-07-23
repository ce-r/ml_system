API_URL="http://localhost:8000"
echo "Testing ML workflow..."

# 1. Register user
echo -e "\n1. Registering user..."
RESPONSE=$(curl -s -X POST "$API_URL/api/v1/users/register" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"testpass123"}')
echo "Response: $RESPONSE"

# Extract token more carefully
TOKEN=$(echo $RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
echo "Token: $TOKEN"

# 2. Create a simple model training request
echo -e "\n2. Training model..."
curl -s -X POST "$API_URL/api/v1/models/train" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test_model",
    "type": "classification",
    "parameters": {"epochs": 10, "batch_size": 32}
  }' | jq .

echo -e "\nWorkflow test completed!"
