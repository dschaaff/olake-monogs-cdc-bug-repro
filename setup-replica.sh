#!/bin/bash
set -e

echo "Waiting for MongoDB to be ready..."
sleep 10

echo "Initializing replica set..."
mongosh --host mongodb:27017 --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27017" }
  ]
})
'

echo "Waiting for replica set to be ready..."
sleep 15

echo "Checking replica set status..."
mongosh --host mongodb:27017 --eval 'rs.status()'

echo "Replica set setup complete!"