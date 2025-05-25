#! /bin/bash

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume

## CACHES
echo "Creating caches folder"
sudo mkdir -p /volume/caches
# ExESDB
echo "creating ExESDB data folders"
sudo mkdir -p \
  /volume/ex-esdb/data0 \
  /volume/ex-esdb/data1 \
  /volume/ex-esdb/data2 \
  /volume/ex-esdb/data3 \
  /volume/ex-esdb/data4

sudo chown "$USER" -R /volume/

docker-compose -f ex-esdb-clique1.yaml \
  down

docker-compose -f ex-esdb-clique1.yaml \
  up \
  --remove-orphans \
  --build \
  -d
