#! /bin/bash

echo "PATH=${PATH}"
echo "EX_ESDB_SEED_NODES=${EX_ESDB_SEED_NODES}"
echo "EX_ESDB_COOKIE=${EX_ESDB_COOKIE}"

echo "stored COOKIE:"
cat ~/.erlang.cookie

sleep 10

exec /system/bin/ex_esdb start
