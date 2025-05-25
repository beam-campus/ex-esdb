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

docker swarm leave --force

docker network rm esdb-net

docker build -t local/ex-esdb ../system

docker swarm init

docker stack rm ex-esdb

docker stack deploy \
  -c deploy-ex-esdb-clique1.yaml \
  -d \
  ex-esdb
