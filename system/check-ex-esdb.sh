#!/bin/bash

epmd -names | grep -q ex-esdb &&
  erl -noshell \
    -name "health@$(hostname)" \
    -setcookie "$EX_ESDB_COOKIE" \
    -eval 'case khepri:is_connected() of true -> halt(0); _ -> halt(1) end.'
