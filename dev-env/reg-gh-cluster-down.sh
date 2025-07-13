#! /bin/bash

docker-compose \
  -f reg-gh-store-volumes.yaml \
  -f reg-gh-network.yaml \
  -f reg-gh-store-cluster.yaml \
  --profile cluster \
  -p reg-gh \
  down
