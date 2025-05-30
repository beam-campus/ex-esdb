#! /bin/bash

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume

## CACHES
echo "Recreating caches folder"
rm -rf /volume/caches
sudo mkdir -p /volume/caches
# ExESDB
echo "Recreating ExESDB data folders"
sudo rm -rf /volume/ex-esdb
sudo mkdir -p \
  /volume/ex-esdb/data0 \
  /volume/ex-esdb/data1 \
  /volume/ex-esdb/data2 \
  /volume/ex-esdb/data3 \
  /volume/ex-esdb/data4

sudo chown "$USER" -R /volume/

docker swarm leave --force

docker network rm esdb-net

docker build -t local/ex-esdb ../system

docker swarm init

docker stack rm ex-esdb

docker stack deploy \
  -c deploy-ex-esdb-clique1.yaml \
  -d \
  ex-esdb
