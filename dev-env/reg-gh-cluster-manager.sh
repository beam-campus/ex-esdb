#!/bin/bash

# Regulate Greenhouse Cluster Manager
# Manages the core reg-gh cluster with chaos engineering capabilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Environment mode (dev/prod)
ENVIRONMENT_MODE="dev"

# Cluster configuration
CLUSTER_FILES="reg-gh-store-volumes.yaml,ex-esdb-network.yaml,reg-gh-store-cluster.yaml"
CLUSTER_PROJECT="reg-gh"
CLUSTER_DESCRIPTION="3 nodes (reg-gh-0,1,2)"

# Function to print colored text
print_color() {
  local color=$1
  local text=$2
  echo -e "${color}${text}${NC}"
}

# Function to print header
print_header() {
  clear
  print_color $CYAN "╔══════════════════════════════════════════════════════════════╗"
  print_color $CYAN "║                 'Regulate Greenhouse' Cluster                 ║"
  print_color $CYAN "║                                                              ║"
  print_color $CYAN "║           LibCluster + Khepri Coordination                   ║"
  print_color $CYAN "╚══════════════════════════════════════════════════════════════╝"
  echo
}

# Function to get cluster status
get_cluster_status() {
  local filter_pattern="name=^reg-gh-[0-2]$"
  
  local running_containers=$(docker ps --filter "$filter_pattern" --format "{{.Names}}" | wc -l 2>/dev/null || echo "0")
  local total_containers=$(docker ps -a --filter "$filter_pattern" --format "{{.Names}}" | wc -l 2>/dev/null || echo "0")

  if [[ $running_containers -eq 0 ]] && [[ $total_containers -eq 0 ]]; then
    echo -e "${BLUE}●${NC} Not created"
  elif [[ $running_containers -eq 0 ]]; then
    echo -e "${RED}●${NC} Stopped ($total_containers containers)"
  elif [[ $running_containers -eq $total_containers ]] && [[ $total_containers -gt 0 ]]; then
    echo -e "${GREEN}●${NC} Running ($running_containers nodes)"
  else
    echo -e "${YELLOW}●${NC} Partial ($running_containers/$total_containers nodes)"
  fi
}

# Function to show cluster status
show_status() {
  print_header
  print_color $WHITE "Current Cluster Status:"
  echo

  printf "  %-12s %s %s\\n" "reg-gh" "$(get_cluster_status)" "($CLUSTER_DESCRIPTION)"

  echo
  print_color $CYAN "Network Status:"
  if docker network ls | grep -q "ex-esdb-net"; then
    echo -e "  ex-esdb-net    ${GREEN}●${NC} Available"
  else
    echo -e "  ex-esdb-net    ${RED}●${NC} Not found"
  fi

  echo
  print_color $CYAN "Volume Status:"
  if [[ -d "/volume/reg-gh-store" ]]; then
    local size=$(du -sh /volume/reg-gh-store 2>/dev/null | cut -f1)
    echo -e "  /volume/reg-gh-store    ${GREEN}●${NC} Available ($size)"
  else
    echo -e "  /volume/reg-gh-store    ${RED}●${NC} Not found"
  fi
}

# Function to start the cluster
start_cluster() {
  print_color $YELLOW "Starting Regulate Greenhouse cluster ($CLUSTER_DESCRIPTION)..."
  echo

  # Convert comma-separated files to -f arguments
  local compose_args=""
  IFS=',' read -ra file_array <<<"$CLUSTER_FILES"
  for file in "${file_array[@]}"; do
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
      compose_args="$compose_args -f $file"
    else
      print_color $RED "Error: File $file not found!"
      return 1
    fi
  done

  print_color $CYAN "Creating data directories for reg-gh store..."
  sudo mkdir -p /volume/reg-gh-store/{data0,data1,data2}
  sudo chown "$USER" -R /volume/

  cd "$SCRIPT_DIR"
  docker-compose $compose_args --profile cluster -p $CLUSTER_PROJECT up --remove-orphans --build -d

  if [[ $? -eq 0 ]]; then
    print_color $GREEN "✓ Regulate Greenhouse cluster started successfully!"
  else
    print_color $RED "✗ Failed to start Regulate Greenhouse cluster"
  fi
}

# Function to stop the cluster
stop_cluster() {
  print_color $YELLOW "Stopping Regulate Greenhouse cluster..."
  echo

  # Convert comma-separated files to -f arguments
  local compose_args=""
  IFS=',' read -ra file_array "$CLUSTER_FILES"
  for file in "${file_array[@]}"; do
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
      compose_args="$compose_args -f $file"
    fi
  done

  cd "$SCRIPT_DIR"
  docker-compose $compose_args --profile cluster -p $CLUSTER_PROJECT down

  if [[ $? -eq 0 ]]; then
    print_color $GREEN "✓ Regulate Greenhouse cluster stopped successfully!"
  else
    print_color $RED "✗ Failed to stop Regulate Greenhouse cluster"
  fi
}

# Function to restart the cluster
restart_cluster() {
  stop_cluster
  echo
  start_cluster
}

# Function to show logs
show_logs() {
  print_color $YELLOW "Showing logs for Regulate Greenhouse cluster..."
  echo
  print_color $CYAN "Press Ctrl+C to exit log view"
  echo

  docker-compose -p $CLUSTER_PROJECT logs -f
}

# Function to clean all data
clean_all_data() {
  print_color $RED "⚠️  WARNING: This will delete ALL cluster data!"
  echo
  read -p "Are you sure you want to continue? (yes/no): " confirm

  if [[ "$confirm" == "yes" ]]; then
    print_color $YELLOW "Stopping cluster..."
    stop_cluster > /dev/null 2>&1

    print_color $YELLOW "Removing data directories..."
    sudo rm -rf /volume/reg-gh-store/*

    print_color $YELLOW "Removing Docker volumes..."
    docker volume prune -f

    print_color $GREEN "✓ All data cleaned successfully!"
  else
    print_color $CYAN "Operation cancelled."
  fi
}

# Function to show resource usage
show_resource_usage() {
  print_color $YELLOW "Docker Resource Usage:"
  echo

  # Show running containers
  print_color $CYAN "Running Containers:"
  docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}" | grep -E "(NAMES|reg-gh-)"
  echo

  # Show resource consumption
  print_color $CYAN "Resource Consumption:"
  docker stats --no-stream --format "table {{.Container}}\\t{{.CPUPerc}}\\t{{.MemUsage}}" | grep -E "(CONTAINER|reg-gh-)"
  echo

  # Show disk usage
  print_color $CYAN "Volume Usage:"
  docker system df
}

# Helper to get a random running container
get_random_running_node() {
  local running_nodes
  running_nodes=($(docker ps --filter "name=^reg-gh-" --format "{{.Names}}" 2>/dev/null))

  if [ ${#running_nodes[@]} -eq 0 ]; then
    echo ""
  else
    echo "${running_nodes[$((RANDOM % ${#running_nodes[@]}))]}"
  fi
}

# Chaos engineering functions
kill_random_node() {
  print_color $YELLOW "🔥 Initiating chaos: Killing a random node..."
  local node_to_kill=$(get_random_running_node)

  if [ -z "$node_to_kill" ]; then
    print_color $RED "No running nodes to kill."
  else
    print_color $RED "💥 Killing node: $node_to_kill"
    docker kill "$node_to_kill"
    print_color $GREEN "✓ Chaos action complete."
  fi
}

stop_random_node() {
  print_color $YELLOW "🔥 Initiating chaos: Stopping a random node gracefully..."
  local node_to_stop=$(get_random_running_node)

  if [ -z "$node_to_stop" ]; then
    print_color $RED "No running nodes to stop."
  else
    print_color $RED "🛑 Stopping node: $node_to_stop"
    docker stop "$node_to_stop"
    print_color $GREEN "✓ Chaos action complete."
  fi
}

pause_random_node() {
  print_color $YELLOW "🔥 Initiating chaos: Pausing a random node..."
  local node_to_pause=$(get_random_running_node)

  if [ -z "$node_to_pause" ]; then
    print_color $RED "No running nodes to pause."
  else
    print_color $RED "⏸️ Pausing node: $node_to_pause (simulates unresponsiveness)"
    docker pause "$node_to_pause"
    print_color $GREEN "✓ Chaos action complete. The cluster should see this node as unhealthy/unreachable."
  fi
}

unpause_all_nodes() {
  print_color $YELLOW "🧊 Recovering from chaos: Unpausing all paused nodes..."
  local paused_nodes
  paused_nodes=($(docker ps --filter "status=paused" --filter "name=^reg-gh-" --format "{{.Names}}" 2>/dev/null))

  if [ ${#paused_nodes[@]} -eq 0 ]; then
    print_color $GREEN "No paused nodes found."
  else
    for node in "${paused_nodes[@]}"; do
      print_color $CYAN "▶️ Resuming node: $node"
      docker unpause "$node"
    done
    print_color $GREEN "✓ All paused nodes have been resumed."
  fi
}

# Function to show main menu
show_menu() {
  print_header
  show_status
  echo
  print_color $WHITE "Available Actions:"
  echo
  print_color $GREEN "  [s] Show Status"
  print_color $GREEN "  [u] Show Resource Usage"
  echo
  print_color $BLUE "  [1] Start Cluster"
  print_color $YELLOW "  [2] Stop Cluster"
  print_color $PURPLE "  [3] Restart Cluster"
  echo
  print_color $CYAN "  [l] Show Logs"
  echo
  print_color $RED "  [🔥] === CHAOS ENGINEERING ==="
  print_color $RED "  [ck] Kill Random Node (hard crash)"
  print_color $RED "  [cs] Stop Random Node (graceful)"
  print_color $RED "  [cp] Pause Random Node (freeze)"
  print_color $GREEN "  [cr] Resume All Paused Nodes"
  echo
  print_color $RED "  [c] Clean All Data"
  echo
  if [[ -n "$EZ_CLUSTER_PARENT" ]]; then
    print_color $BLUE "  [b] ⬅️  Back to EZ Cluster Menu"
  else
    print_color $WHITE "  [q] 👋 Quit"
  fi
  echo
}

# Main loop
main() {
  while true; do
    show_menu
    echo -n "Enter your choice: "
    read -r choice
    echo

    case $choice in
    s | S) continue ;;
    u | U) show_resource_usage ;;
    1) start_cluster ;;
    2) stop_cluster ;;
    3) restart_cluster ;;
    l | L) show_logs ;;
    ck | CK) kill_random_node ;;
    cs | CS) stop_random_node ;;
    cp | CP) pause_random_node ;;
    cr | CR) unpause_all_nodes ;;
    c | C) clean_all_data ;;
    b | B)
      if [[ -n "$EZ_CLUSTER_PARENT" ]]; then
        print_color $GREEN "Returning to EZ Cluster Menu..."
        return 0
      else
        print_color $RED "Invalid choice. Please try again."
      fi
      ;;
    q | Q)
      print_color $GREEN "Goodbye!"
      exit 0
      ;;
    *)
      print_color $RED "Invalid choice. Please try again."
      ;;
    esac

    echo
    print_color $CYAN "Press Enter to continue..."
    read
  done
}

# Check if running as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
