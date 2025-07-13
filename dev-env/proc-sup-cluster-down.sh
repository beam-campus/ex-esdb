#!/bin/bash

docker-compose \
  -f proc-sup-store-volumes.yaml \
  -f proc-sup-network.yaml \
  -f proc-sup-store-cluster.yaml \
  --profile cluster \
  -p proc-sup \
  down
