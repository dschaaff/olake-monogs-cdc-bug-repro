# MongoDB CDC Resume Token Bug Reproduction

This reproduction demonstrates a bug in olake's MongoDB CDC implementation where changes made between sync runs are not captured due to incorrect resume token handling.

## Bug Description

**Issue**: MongoDB CDC fails to sync documents inserted between olake runs, even though the resume token is being saved and loaded correctly.

**Root Cause**: The resume token is being extracted as a string and wrapped incorrectly when passed to MongoDB's `SetResumeAfter()`. MongoDB expects the complete resume token object in its original BSON format.

## Environment

- **MongoDB**: 6.0 (replica set required for CDC)
- **olake**: v0.2.3 MongoDB source
- **Test Data**: Simple orders collection with CDC sync mode

## Prerequisites

- Docker and Docker Compose
- `mongosh` CLI tool
- `jq` for JSON processing

## Quick Start

1. **Start MongoDB replica set:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for setup to complete (about 30 seconds):**
   ```bash
   docker-compose logs -f mongodb-setup
   ```

3. **Run the reproduction script:**
   ```bash
   chmod +x reproduce-bug.sh
   ./reproduce-bug.sh
   ```

## Expected vs Actual Behavior

### Expected Behavior ✅
1. First run: Sync 3 initial documents
2. Insert new document: `ORD-004-NEW`
3. Second run: Sync the new document (total: 4 documents)

### Actual Behavior ❌
1. First run: Sync 3 initial documents ✅
2. Insert new document: `ORD-004-NEW` ✅
3. Second run: **Fails to sync the new document** ❌ (total: still 3 documents)

## Reproduction Steps (Manual)

1. **Start the environment:**
   ```bash
   docker-compose up -d
   sleep 30  # Wait for replica set initialization
   ```

2. **Run initial sync:**
   ```bash
   docker run --rm \
     --network host \
     -v "$(pwd)":/workspace \
     -w /workspace \
     olakego/source-mongodb:v0.2.3 \
     sync \
     --source-config source-config.json \
     --destination-config destination-config.json \
     --catalog catalog.json
   ```

3. **Verify initial sync (should show 3 documents):**
   ```bash
   wc -l output/mongodb_testdb/orders.jsonl
   ```

4. **Insert new document:**
   ```bash
   mongosh --host localhost:27017 -u testuser -p testpass --authenticationDatabase admin testdb --eval '
   db.orders.insertOne({
       orderID: "ORD-004-NEW",
       customerName: "Alice Brown",
       amount: 150.00,
       status: "pending",
       createdAt: new Date()
   });'
   ```

5. **Run sync again:**
   ```bash
   docker run --rm \
     --network host \
     -v "$(pwd)":/workspace \
     -w /workspace \
     olakego/source-mongodb:v0.2.3 \
     sync \
     --source-config source-config.json \
     --destination-config destination-config.json \
     --catalog catalog.json
   ```

6. **Check results (should show 4 documents, but will show 3):**
   ```bash
   wc -l output/mongodb_testdb/orders.jsonl
   cat output/mongodb_testdb/orders.jsonl | jq -r '.orderID'
   ```

## Debugging Information

**State file after first run:**
```bash
cat state.json | jq .
```
Shows the resume token is saved: `"_data": "8268CC46AC000000022B0229296E04"`

**MongoDB verification that change streams work:**
```bash
# In another terminal, run this to verify CDC works:
mongosh --host localhost:27017 -u testuser -p testpass --authenticationDatabase admin testdb --eval '
const cursor = db.orders.watch();
while (cursor.hasNext()) {
    print("Change detected:", JSON.stringify(cursor.next()));
}
'
# Then insert a document in another terminal - you should see the change
```

## File Structure

```
bug-reproduction/
├── docker-compose.yml          # MongoDB 6.0 replica set
├── setup-replica.sh           # Replica set initialization
├── init-data.js              # Initial test data
├── source-config.json        # MongoDB connection config
├── destination-config.json   # Local file output config
├── catalog.json              # Stream configuration (CDC mode)
├── reproduce-bug.sh          # Automated reproduction script
└── README.md                 # This file
```

## Technical Details

**Current Broken Code** (in olake MongoDB driver):
```go
// Stores only _data field as string
prevResumeToken = (*resumeToken).Lookup("_data").StringValue()

// Wraps string in map - WRONG FORMAT
changeStreamOpts = changeStreamOpts.SetResumeAfter(map[string]any{"_data": resumeToken})
```

**Correct Fix**:
```go
// Store complete resume token object
prevResumeToken = *resumeToken  // Complete BSON token

// Use complete token directly
changeStreamOpts = changeStreamOpts.SetResumeAfter(resumeToken)
```

## Cleanup

```bash
docker-compose down -v
rm -rf output/ state.json
```

## Exit Codes

- `0`: Bug NOT reproduced (CDC working correctly)
- `1`: Bug reproduced (CDC failed to sync new document)

## Files Affected

The bug is in the olake MongoDB source driver, specifically:
- `drivers/mongodb/internal/cdc.go` - Resume token handling
- `PreCDC()` function - Token storage
- `StreamChanges()` function - Token usage with `SetResumeAfter()`