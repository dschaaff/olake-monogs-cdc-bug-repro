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
echo "{}" >state.json

# Function to count documents in output
count_output_documents() {
    if [ -f "stats.json" ]; then
        jq -r '.["Synced Records"] // 0' stats.json
    else
        echo "0"
    fi
}

run_olake_sync() {
    docker run --rm \
        --network host \
        -v "$(pwd)":/workspace \
        olakego/source-mongodb:v0.2.3 \
        sync \
        --config /workspace/source-config.json \
        --destination /workspace/destination-config.json \
        --catalog /workspace/discovered-catalog.json \
        --state /workspace/state.json

}

insert_document() {
    local random_order_id="ORD-$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')"
    local customer_names=("Alice Smith" "Bob Johnson" "Charlie Davis" "Diana Miller" "Eve Wilson")
    local random_customer_name="${customer_names[$((RANDOM % ${#customer_names[@]}))]}"
    local random_amount=$(awk -v min=50 -v max=500 'BEGIN{srand(); print min+rand()*(max-min)}')
    local statuses=("pending" "completed" "shipped" "cancelled")
    local random_status="${statuses[$((RANDOM % ${#statuses[@]}))]}"

    docker exec mongos mongosh --username mongodb --password secure_password123 --authenticationDatabase admin olake_mongodb_test --eval "
db.test_collection.insertOne({
    _id: ObjectId(),
    orderID: \"$random_order_id\",
    customerName: \"$random_customer_name\",
    amount: $random_amount,
    status: \"$random_status\",
    createdAt: new Date()
});
"
}

echo -e "${YELLOW}Step 1: Run olake discover to generate catalog${NC}"
# docker run --rm \
#     --network host \
#     -v "$(pwd)":/workspace \
#     olakego/source-mongodb:v0.2.3 \
#     discover \
#     --config /workspace/source-config.json

echo -e "${GREEN}Discovery complete. Using discovered catalog.${NC}"

echo -e "${YELLOW}Step 2: Run initial olake sync${NC}"

while true; do
    echo -e "${YELLOW}Insert a new document into MongoDB${NC}"
    insert_document
    run_olake_sync
done
