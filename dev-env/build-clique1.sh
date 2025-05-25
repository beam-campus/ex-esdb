#! /bin/bash

docker-compose -f ex-esdb-clique1.yaml \
  build \
  --no-cache \
  --progress=plain
