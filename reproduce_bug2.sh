#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

docker exec -it minio mc mb /data/olake-data
echo -e "${BLUE}=== MongoDB CDC Resume Token Bug Reproduction ===${NC}"

# Clean up previous runs
echo -e "${YELLOW}Cleaning up previous runs...${NC}"
rm -rf output/ state.json stats.json
echo "{}" > state.json

# Function to count documents in output
count_output_documents() {
    if [ -f "stats.json" ]; then
        jq -r '.["Synced Records"] // 0' stats.json
    else
        echo "0"
    fi
}

# Function to check if the new document exists in MongoDB
check_new_document_exists() {
    docker exec primary_mongo mongosh --username mongodb --password secure_password123 --authenticationDatabase admin olake_mongodb_test --quiet --eval 'print(db.test_collection.countDocuments({orderID: "ORD-004-NEW"}));' 2>/dev/null || echo "0"
}

echo -e "${YELLOW}Step 1: Run olake discover to generate catalog${NC}"
docker run --rm \
    --network host \
    -v "$(pwd)":/workspace \
    olakego/source-mongodb:v0.2.3 \
    discover \
    --config /workspace/source-config.json

echo -e "${GREEN}Discovery complete. Using discovered catalog.${NC}"

echo -e "${YELLOW}Step 2: Run initial olake sync (should sync 3 initial documents)${NC}"
docker run --rm \
    --network host \
    -v "$(pwd)":/workspace \
    olakego/source-mongodb:v0.2.3 \
    sync \
    --config /workspace/source-config.json \
    --destination /workspace/destination-config.json \
    --catalog /workspace/discovered-catalog.json \
    --state /workspace/state.json

echo -e "${YELLOW}Step 3: Insert a new document into MongoDB${NC}"
docker exec primary_mongo mongosh --username mongodb --password secure_password123 --authenticationDatabase admin olake_mongodb_test --eval '
db.test_collection.insertOne({
    _id: ObjectId(),
    orderID: "ORD-004-NEW",
    customerName: "Alice Brown",
    amount: 150.00,
    status: "pending",
    createdAt: new Date()
});
print("Inserted new document with orderID: ORD-004-NEW");
'

echo -e "${YELLOW}Step 4: Run olake sync again (should pick up the new document)${NC}"
docker run --rm \
    --network host \
    -v "$(pwd)":/workspace \
    olakego/source-mongodb:v0.2.3 \
    sync \
    --config /workspace/source-config.json \
    --destination /workspace/destination-config.json \
    --catalog /workspace/discovered-catalog.json

echo -e "${YELLOW}Step 3: Insert a new document into MongoDB${NC}"
docker exec primary_mongo mongosh --username mongodb --password secure_password123 --authenticationDatabase admin olake_mongodb_test --eval '
db.test_collection.insertOne({
    _id: ObjectId(),
    orderID: "ORD-005-NEW",
    customerName: "Alice Brown",
    amount: 150.00,
    status: "pending",
    createdAt: new Date()
});
print("Inserted new document with orderID: ORD-004-NEW");
'

echo -e "${YELLOW}Step 4: Run olake sync again (should pick up the new document)${NC}"
docker run --rm \
    --network host \
    -v "$(pwd)":/workspace \
    olakego/source-mongodb:v0.2.3 \
    sync \
    --config /workspace/source-config.json \
    --destination /workspace/destination-config.json \
    --catalog /workspace/discovered-catalog.json

echo -e "${YELLOW}Step 3: Insert a new document into MongoDB${NC}"
docker exec primary_mongo mongosh --username mongodb --password secure_password123 --authenticationDatabase admin olake_mongodb_test --eval '
db.test_collection.insertOne({
    _id: ObjectId(),
    orderID: "ORD-006-NEW",
    customerName: "Alice Brown",
    amount: 150.00,
    status: "pending",
    createdAt: new Date()
});
print("Inserted new document with orderID: ORD-006-NEW");
'

echo -e "${YELLOW}Step 4: Run olake sync again (should pick up the new document)${NC}"
docker run --rm \
    --network host \
    -v "$(pwd)":/workspace \
    olakego/source-mongodb:v0.2.3 \
    sync \
    --config /workspace/source-config.json \
    --destination /workspace/destination-config.json \
    --catalog /workspace/discovered-catalog.json
