#!/bin/bash

# proc-sup Core Cluster (3 nodes: 0, 1, 2)
# Use proc-sup-start-core.sh, proc-sup-start-extended.sh, or proc-sup-start-massive.sh for tiered clusters

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume
docker-compose \
  -f proc-sup-store-volumes.yaml \
  -f proc-sup-network.yaml \
  -f proc-sup-store-cluster.yaml \
  --profile cluster \
  -p proc-sup \
  down

## CACHES
echo "Removing caches folder"
sudo rm -rf /volume/caches
echo "Creating caches folder"
sudo mkdir -p /volume/caches
# proc-sup
echo "removing proc-sup data folders"
sudo rm -rf /volume/proc-sup-store
echo "creating proc-sup data folders"
sudo mkdir -p \
  /volume/proc-sup-store/data0 \
  /volume/proc-sup-store/data1 \
  /volume/proc-sup-store/data2 \
  /volume/proc-sup-store/data3 \
  /volume/proc-sup-store/data4

sudo chown "$USER" -R /volume/

docker-compose \
  -f proc-sup-store-volumes.yaml \
  -f proc-sup-network.yaml \
  -f proc-sup-store-cluster.yaml \
  --profile cluster \
  -p proc-sup \
  up \
  --remove-orphans \
  --build \
  -d
