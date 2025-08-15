#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values - all files are in the same directory now
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.cluster"
COMPOSE_FILE="$SCRIPT_DIR/reckon-db-cluster.yaml"
NETWORK_FILE="$SCRIPT_DIR/reg-gh-network.yaml"

print_usage() {
    echo "Usage: $0 {up|down|build|logs|status|restart|health}"
    echo ""
    echo "Commands:"
    echo "  up      - Start ReckonDB cluster services"
    echo "  down    - Stop ReckonDB cluster services"
    echo "  build   - Build ReckonDB Docker image"
    echo "  logs    - Show ReckonDB logs"
    echo "  status  - Show cluster status"
    echo "  restart - Restart ReckonDB services"
    echo "  health  - Check cluster health"
    echo ""
    echo "Environment:"
    echo "  ENV_FILE=$ENV_FILE"
    echo "  COMPOSE_FILE=$COMPOSE_FILE"
}

ensure_network() {
    echo -e "${BLUE}Ensuring ex-esdb-net network exists...${NC}"
    if ! docker network inspect ex-esdb-net >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating ex-esdb-net network...${NC}"
        docker compose -f "$NETWORK_FILE" up -d
    else
        echo -e "${GREEN}Network ex-esdb-net already exists.${NC}"
    fi
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        echo -e "${BLUE}Loading environment from $ENV_FILE${NC}"
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
        echo -e "${RED}Environment file $ENV_FILE not found!${NC}"
        exit 1
    fi
}

cluster_up() {
    load_env
    ensure_network
    
    echo -e "${BLUE}Starting ReckonDB cluster...${NC}"
    docker compose -f "$COMPOSE_FILE" --profile cluster up -d
    
    echo -e "${GREEN}ReckonDB cluster started successfully!${NC}"
    echo -e "${BLUE}Services:${NC}"
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    echo -e "${BLUE}Access URLs:${NC}"
    echo -e "  ReckonDB Admin Portal: ${GREEN}http://localhost:4000${NC}"
    echo -e "  ReckonDB gRPC API:     ${GREEN}localhost:50051${NC}"
}

cluster_down() {
    echo -e "${BLUE}Stopping ReckonDB cluster...${NC}"
    docker compose -f "$COMPOSE_FILE" --profile cluster down
    echo -e "${GREEN}ReckonDB cluster stopped successfully!${NC}"
}

build_image() {
    load_env
    echo -e "${BLUE}Building ReckonDB Docker image...${NC}"
    docker compose -f "$COMPOSE_FILE" build reckon-db
    echo -e "${GREEN}ReckonDB image built successfully!${NC}"
}

show_logs() {
    echo -e "${BLUE}Showing ReckonDB logs...${NC}"
    docker compose -f "$COMPOSE_FILE" logs -f reckon-db
}

show_status() {
    echo -e "${BLUE}ReckonDB Cluster Status:${NC}"
    echo ""
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    
    echo -e "${BLUE}Network Status:${NC}"
    docker network inspect ex-esdb-net --format '{{json .}}' | jq -r '.Containers | to_entries[] | "\(.value.Name): \(.value.IPv4Address)"' 2>/dev/null || echo "Install jq for detailed network info"
    echo ""
    
    echo -e "${BLUE}Port Mappings:${NC}"
    docker port reckon-db 2>/dev/null || echo "ReckonDB container not running"
}

restart_services() {
    echo -e "${BLUE}Restarting ReckonDB services...${NC}"
    docker compose -f "$COMPOSE_FILE" restart reckon-db
    echo -e "${GREEN}ReckonDB services restarted!${NC}"
}

check_health() {
    echo -e "${BLUE}Checking ReckonDB health...${NC}"
    
    # Check if container is running
    if ! docker compose -f "$COMPOSE_FILE" ps reckon-db | grep -q "Up"; then
        echo -e "${RED}ReckonDB container is not running!${NC}"
        return 1
    fi
    
    # Check health status
    HEALTH=$(docker inspect reckon-db --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    echo -e "Health Status: ${GREEN}$HEALTH${NC}"
    
    # Check HTTP endpoint
    echo -e "${BLUE}Testing HTTP endpoint...${NC}"
    if curl -f -s http://localhost:4000/health >/dev/null; then
        echo -e "${GREEN}HTTP endpoint is healthy${NC}"
    else
        echo -e "${RED}HTTP endpoint is not responding${NC}"
    fi
    
    # Check gRPC port
    echo -e "${BLUE}Testing gRPC port...${NC}"
    if ss -tuln | grep -q ":50051"; then
        echo -e "${GREEN}gRPC port is listening${NC}"
    else
        echo -e "${RED}gRPC port is not listening${NC}"
    fi
    
    # Show recent logs
    echo -e "${BLUE}Recent logs (last 20 lines):${NC}"
    docker compose -f "$COMPOSE_FILE" logs --tail=20 reckon-db
}

# Main execution
case "${1:-}" in
    up)
        cluster_up
        ;;
    down)
        cluster_down
        ;;
    build)
        build_image
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    restart)
        restart_services
        ;;
    health)
        check_health
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
