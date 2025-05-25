#! /bin/bash

## CLEAR ALL DATA
# echo "Clearing all data"
# sudo rm -rf /volume

## EXCALIDRAW
echo "Creating excalidraw folder"
sudo mkdir -p /volume/excalidraw/data

sudo chown "$USER" -R /volume/

docker-compose -f livebook.yml \
  -f excalidraw.yml \
  -f networks.yml \
  down

docker-compose -f livebook.yml \
  -f excalidraw.yml \
  -f networks.yml \
  up --remove-orphans --build -d
