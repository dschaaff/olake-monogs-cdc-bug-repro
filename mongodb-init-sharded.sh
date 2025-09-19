#!/bin/bash

set -e

echo "Waiting for keyfile..."
while [ ! -f /etc/mongodb/pki/keyfile ]; do
    sleep 1
done

echo "Keyfile found, starting mongos initialization process..."

# Wait for all components to be ready
echo "Waiting for config servers to be ready..."
until mongosh --host config1:27019 --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; do
    echo "Waiting for config1..."
    sleep 2
done

until mongosh --host config2:27019 --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; do
    echo "Waiting for config2..."
    sleep 2
done

until mongosh --host config3:27019 --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; do
    echo "Waiting for config3..."
    sleep 2
done

echo "Waiting for shard servers to be ready..."
until mongosh --host shard1_1:27018 --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; do
    echo "Waiting for shard1_1..."
    sleep 2
done

echo "All servers are ready, initializing replica sets..."

# Initialize config server replica set
echo "Initializing config server replica set..."
mongosh --host config1:27019 --eval "
rs.initiate({
  _id: 'configrs',
  configsvr: true,
  members: [
    { _id: 0, host: 'config1:27019' },
    { _id: 1, host: 'config2:27019' },
    { _id: 2, host: 'config3:27019' }
  ]
})
"

# Wait for config replica set to be ready
echo "Waiting for config replica set PRIMARY..."
for i in {1..60}; do
    STATE=$(mongosh --host config1:27019 --quiet --eval "rs.isMaster().ismaster" 2>/dev/null || echo "false")
    if [ "$STATE" = "true" ]; then
        echo "Config replica set PRIMARY ready"
        break
    fi
    echo "Still waiting for config PRIMARY... ($i/60)"
    sleep 2
done

# Initialize shard1 replica set
echo "Initializing shard1 replica set..."
mongosh --host shard1_1:27018 --eval "
rs.initiate({
  _id: 'shard1rs',
  members: [
    { _id: 0, host: 'shard1_1:27018' },
    { _id: 1, host: 'shard1_2:27018' },
    { _id: 2, host: 'shard1_3:27018' }
  ]
})
"

# Wait for shard1 replica set to be ready
echo "Waiting for shard1 replica set PRIMARY..."
for i in {1..60}; do
    STATE=$(mongosh --host shard1_1:27018 --quiet --eval "rs.isMaster().ismaster" 2>/dev/null || echo "false")
    if [ "$STATE" = "true" ]; then
        echo "Shard1 replica set PRIMARY ready"
        break
    fi
    echo "Still waiting for shard1 PRIMARY... ($i/60)"
    sleep 2
done


echo "All replica sets initialized. Starting mongos and adding shards..."

# Start mongos in background (without keyfile initially)
echo "Starting mongos..."
mongos --configdb configrs/config1:27019,config2:27019,config3:27019 --bind_ip_all --port 27017 &
MONGOS_PID=$!
echo "Mongos started with PID: $MONGOS_PID"

echo "Waiting for mongos to be ready..."
for i in {1..60}; do
    if mongosh --host localhost:27017 --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; then
        echo "Mongos is ready"
        break
    fi
    echo "Still waiting for mongos... ($i/60)"
    sleep 2
done

# Add shard to the cluster
echo "Adding shard to the cluster..."
mongosh --host localhost:27017 --eval "
sh.addShard('shard1rs/shard1_1:27018,shard1_2:27018,shard1_3:27018');
"

# Create admin user
echo "Creating admin user..."
mongosh --host localhost:27017 --eval "
db = db.getSiblingDB('admin');
db.createUser({
    user: 'admin',
    pwd: 'password',
    roles: [{ role: 'root', db: 'admin' }]
});
"

# Create application database and collections (without sharding for olake compatibility)
echo "Creating database and collections..."
mongosh --host localhost:27017 --eval "
db = db.getSiblingDB('admin');
db.auth('admin', 'password');

// Enable sharding for the database but don't shard the specific collections
sh.enableSharding('olake_mongodb_test');

// Create collections but DO NOT enable sharding on them (for olake compatibility)
db = db.getSiblingDB('olake_mongodb_test');
db.createCollection('test_collection');
db.createCollection('test_collection_two');

// Insert test data
db.test_collection.insertMany([
    {
        _id: ObjectId(),
        orderID: 'ORD-001',
        customerName: 'John Doe',
        amount: 100.50,
        status: 'completed',
        createdAt: new Date()
    },
    {
        _id: ObjectId(),
        orderID: 'ORD-002',
        customerName: 'Jane Smith',
        amount: 250.75,
        status: 'pending',
        createdAt: new Date()
    },
    {
        _id: ObjectId(),
        orderID: 'ORD-003',
        customerName: 'Bob Johnson',
        amount: 75.25,
        status: 'completed',
        createdAt: new Date()
    }
]);

db.test_collection_two.insertMany([
    {
        _id: ObjectId(),
        orderID: 'ORD-001',
        customerName: 'John Doe',
        amount: 100.50,
        status: 'completed',
        createdAt: new Date()
    },
    {
        _id: ObjectId(),
        orderID: 'ORD-002',
        customerName: 'Jane Smith',
        amount: 250.75,
        status: 'pending',
        createdAt: new Date()
    },
    {
        _id: ObjectId(),
        orderID: 'ORD-003',
        customerName: 'Bob Johnson',
        amount: 75.25,
        status: 'completed',
        createdAt: new Date()
    }
]);
print('Inserted test documents');

// Create application user
db = db.getSiblingDB('admin');

try { db.dropUser('mongodb'); } catch(e) { print('User mongodb does not exist, skipping drop'); }

db.createUser({
    user: 'mongodb',
    pwd: 'secure_password123',
    roles: [
        { role: 'readWrite', db: 'olake_mongodb_test' }
    ]
});

try { db.dropRole('splitVectorRole'); } catch(e) { print('Role splitVectorRole does not exist, skipping drop'); }

db.createRole({
    role: 'splitVectorRole',
    privileges: [
        {
            resource: { db: '', collection: '' },
            actions: [ 'splitVector' ]
        }
    ],
    roles: []
});

db.grantRolesToUser('mongodb', [
    { role: 'splitVectorRole', db: 'admin' }
]);

print('Sharded cluster initialization complete!');
print('Cluster status:');
sh.status();
"

echo "Sharded cluster setup complete!"
echo "Applications can connect to mongos at localhost:27017"
echo "Use credentials: admin/password or mongodb/secure_password123"

# Wait for mongos to continue running
wait $MONGOS_PID