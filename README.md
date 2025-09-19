# MongoDB CDC Resume Token Bug Reproduction

This reproduction demonstrates a bug in olake's MongoDB CDC implementation where changes made between sync runs are not captured due to incorrect resume token handling.

## Bug Description

**Issue**: MongoDB CDC fails to detect document changes when connecting through mongos routing due to non-blocking `TryNext()` behavior in the MongoDB Go driver. The change stream opens successfully and resume tokens are handled correctly, but `cursor.TryNext()` returns `false` immediately even when events exist, causing the CDC process to miss all document insertions/updates.

## Environment

## Prerequisites

- Docker and Docker Compose
- `jq` for JSON processing

##

1. **Start Compose Stack:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for setup to complete (about 30 seconds):**
   ```bash
   docker-compose logs -f
   ```

3. **Run the reproduction script:**
   ```bash
   ./reproduce-bug.sh
   ```

The script will write a document to mongo and then run an olake sync in a loop.

## Expected vs Actual Behavior


## Cleanup

```bash
docker-compose down -v
rm -rf output/ state.json
```

