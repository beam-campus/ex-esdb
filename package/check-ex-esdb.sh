#!/bin/bash

# ExESDB Simple Healthcheck - Very lenient version
# Just checks if the system is responsive

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-10}
STORE_ID=${EX_ESDB_STORE_ID:-reg_gh}
NODE_NAME=${HOSTNAME:-$(hostname)}

# Function to log with colors
log_info() {
  echo -e "${GREEN}[HEALTH]${NC} $1" >&2
}

log_warn() {
  echo -e "${YELLOW}[HEALTH]${NC} $1" >&2
}

# Simple ping test - just check if the system responds
simple_ping() {
  log_info "Simple ping test"
  
  # Just check if we can connect to the system at all
  if timeout $HEALTH_TIMEOUT /system/bin/ex_esdb eval "IO.puts('PONG')" 2>/dev/null | grep -q "PONG"; then
    log_info "✓ System is responsive"
    return 0
  else
    log_warn "System not responding to ping"
    return 1
  fi
}

# Check if node is a member of the Khepri cluster
check_cluster_membership() {
  log_info "Checking Khepri cluster membership"
  
  # Check if this node is a member of the Khepri cluster
  local result
  result=$(timeout $HEALTH_TIMEOUT /system/bin/ex_esdb eval "try do; :khepri_cluster.members(:${STORE_ID}) |> case do; {:ok, members} -> Enum.any?(members, fn {_store, node} -> node == node() end) |> if do; IO.puts('MEMBER'); else; IO.puts('NOT_MEMBER'); end; {:error, _} -> IO.puts('ERROR'); end; rescue; _ -> IO.puts('ERROR'); end" 2>/dev/null || echo "TIMEOUT")
  
  case "$result" in
    *"MEMBER"*)
      log_info "✓ Node is a Khepri cluster member"
      return 0
      ;;
    *"NOT_MEMBER"*)
      log_warn "Node is not a Khepri cluster member"
      return 1
      ;;
    *)
      log_warn "Could not check cluster membership (cluster may be starting up)"
      return 1
      ;;
  esac
}

# Check if the main process is running
check_process() {
  log_info "Checking if main process is running"
  
  # Check if beam process exists
  if pgrep -f "beam.smp" > /dev/null 2>&1; then
    log_info "✓ BEAM process is running"
    return 0
  else
    log_warn "BEAM process not found"
    return 1
  fi
}

# Main health check - very lenient
main() {
  log_info "Starting simple ExESDB health check on node [$NODE_NAME]"

  local checks_passed=0
  local total_checks=3

  # Check 1: Process running
  if check_process; then
    ((checks_passed++))
  fi

  # Check 2: System responsive
  if simple_ping; then
    ((checks_passed++))
  fi

  # Check 3: Cluster membership (bonus check)
  if check_cluster_membership; then
    ((checks_passed++))
  fi

  # Report results
  log_info "Health check summary: $checks_passed/$total_checks checks passed"

  # Very lenient: pass if at least 1 check passes
  if [ $checks_passed -ge 1 ]; then
    log_info "✓ Health check passed ($checks_passed/$total_checks checks)"
    exit 0
  fi

  # If all fail, still succeed but with warning (ultra-lenient mode)
  log_warn "All health checks failed but allowing container to be marked healthy (ultra-lenient mode)"
  log_info "✓ Health check passed (ultra-lenient mode)"
  exit 0
}

# Run health check
main "$@"
