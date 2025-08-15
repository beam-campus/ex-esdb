#!/bin/bash

# Exit on any error
set -e

# Set default environment if not specified
export MIX_ENV="${MIX_ENV:-prod}"

# Show current configuration
echo "========================================="
echo "Starting RegGh ExESDB Store"
echo "========================================="
echo "Store ID: ${EX_ESDB_STORE_ID:-reg_gh}"
echo "DB Type: ${EX_ESDB_DB_TYPE:-cluster}"
echo "Node Name: ${RELEASE_NODE:-reg_gh@localhost}"
echo "Data Dir: ${EX_ESDB_DATA_DIR:-/data}"
echo "Cookie: ${EX_ESDB_COOKIE:-***masked***}"
echo "Cluster Secret: ${EX_ESDB_CLUSTER_SECRET:-***masked***}"
echo "Multicast Addr: ${EX_ESDB_GOSSIP_MULTICAST_ADDR:-***masked***}"
echo "========================================="

# Start the release
exec /system/bin/reg_gh start
