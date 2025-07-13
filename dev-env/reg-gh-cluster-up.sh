#! /bin/bash

# reg-gh Core Cluster (3 nodes: 0, 1, 2)
# Use start-core.sh, start-extended.sh, or start-massive.sh for tiered clusters

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume
docker-compose \
  -f reg-gh-store-volumes.yaml \
  -f reg-gh-network.yaml \
  -f reg-gh-store-cluster.yaml \
  --profile cluster \
  -p reg-gh \
  down

## CACHES
echo "Removing caches folder"
sudo rm -rf /volume/caches
echo "Creating caches folder"
sudo mkdir -p /volume/caches
# reg-gh
echo "removing reg-gh data folders"
sudo rm -rf /volume/reg-gh-store
echo "creating reg-gh data folders"
sudo mkdir -p \
  /volume/reg-gh-store/data0 \
  /volume/reg-gh-store/data1 \
  /volume/reg-gh-store/data2 \
  /volume/reg-gh-store/data3 \
  /volume/reg-gh-store/data4

sudo chown "$USER" -R /volume/

docker-compose \
  -f reg-gh-store-volumes.yaml \
  -f reg-gh-network.yaml \
  -f reg-gh-store-cluster.yaml \
  --profile cluster \
  -p reg-gh \
  up \
  --remove-orphans \
  --build \
  -d
