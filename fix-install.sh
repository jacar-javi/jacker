#!/bin/bash

# Fix Fresh Install Issues for Jacker
# This script fixes the errors found in your fresh install

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Jacker Fresh Install Fix Script ===${NC}"
echo ""

# Fix 1: Loki rules directory (already created, but verify)
echo -e "${BLUE}[1/4] Fixing Loki /loki/rules permission issue...${NC}"
if [ ! -d "data/loki/data/rules" ]; then
    mkdir -p data/loki/data/rules
    echo -e "${GREEN}✓ Created data/loki/data/rules directory${NC}"
else
    echo -e "${GREEN}✓ data/loki/data/rules directory already exists${NC}"
fi

# Fix 2: Create crowdsec_db database in PostgreSQL
echo -e "\n${BLUE}[2/4] Creating crowdsec_db database in PostgreSQL...${NC}"
echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Create the database using docker exec
docker compose exec -T postgres psql -U ${POSTGRES_USER:-crowdsec} -d ${POSTGRES_DB:-postgres} -c "SELECT 1 FROM pg_database WHERE datname='crowdsec_db'" | grep -q 1 || \
docker compose exec -T postgres psql -U ${POSTGRES_USER:-crowdsec} -d ${POSTGRES_DB:-postgres} -c "CREATE DATABASE crowdsec_db OWNER ${POSTGRES_USER:-crowdsec};"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ crowdsec_db database created successfully${NC}"
else
    echo -e "${YELLOW}⚠ Database may already exist or there was an issue${NC}"
fi

# Fix 3: Set Redis memory overcommit
echo -e "\n${BLUE}[3/4] Fixing Redis memory overcommit warning...${NC}"
current_value=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "unknown")
echo "Current vm.overcommit_memory value: $current_value"

if [ "$current_value" != "1" ]; then
    echo -e "${YELLOW}⚠ vm.overcommit_memory is not set to 1${NC}"
    echo -e "${YELLOW}To fix this permanently, you need to run on the HOST (not in container):${NC}"
    echo -e "${YELLOW}  sudo sysctl vm.overcommit_memory=1${NC}"
    echo -e "${YELLOW}  echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf${NC}"
else
    echo -e "${GREEN}✓ vm.overcommit_memory is already set to 1${NC}"
fi

# Fix 4: Restart affected services
echo -e "\n${BLUE}[4/4] Restarting affected services...${NC}"
echo "Restarting Loki..."
docker compose restart loki
echo "Restarting Promtail..."
docker compose restart promtail
echo "Restarting CrowdSec..."
docker compose restart crowdsec

echo ""
echo -e "${GREEN}=== Fix script completed! ===${NC}"
echo ""
echo -e "${BLUE}Checking service health...${NC}"
echo "Waiting 10 seconds for services to stabilize..."
sleep 10

docker compose ps

echo ""
echo -e "${BLUE}To view logs and verify fixes:${NC}"
echo "  docker compose logs -f loki crowdsec prometheus"
echo ""
echo -e "${BLUE}To check for remaining errors:${NC}"
echo "  docker compose logs | grep -i error"
