#! /bin/bash

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume

## CACHES
echo "Removing caches folder"
sudo rm -rf /volume/caches
echo "Creating caches folder"
sudo mkdir -p /volume/caches
# ExESDB
echo "removing ExESDB data folders"
sudo rm -rf /volume/ex-esdb

echo "creating ExESDB data folders"
sudo mkdir -p \
  /volume/ex-esdb/data0 \
  /volume/ex-esdb/data1 \
  /volume/ex-esdb/data2 \
  /volume/ex-esdb/data3 \
  /volume/ex-esdb/data4

sudo chown "$USER" -R /volume/

docker-compose -f ex-esdb-cluster.yaml \
  down

docker-compose -f ex-esdb-cluster.yaml \
  up \
  --remove-orphans \
  --build \
  -d
