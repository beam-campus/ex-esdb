#!/bin/bash

echo "Checking if ex_esdb with store id [$EX_ESDB_STORE_ID] is up on [$(hostname)]...for clique [$EX_ESDB_COOKIE]"

epmd -names | grep -q ex_esdb &&
  /system/bin/ex_esdb eval "if :khepri_cluster.is_store_running(:${EX_ESDB_STORE_ID}) do :init.stop(0) else :init.stop(1) end"
# erl -noshell \
#   -name "health@$(hostname)" \
#   -setcookie "$EX_ESDB_COOKIE" \
#   -eval 'case khepri_cluster:is_store_running($EX_ESDB_STORE_ID) of true -> halt(0); _ -> halt(1) end.'
