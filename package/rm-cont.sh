#! /bin/bash
docker container stop $(docker container list -qa) 
docker container rm -f $(docker container list -qa) 