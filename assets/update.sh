#!/usr/bin/env bash
#
# Script: update.sh
# Description: Update all Jacker Docker images and containers with rollback support
# Usage: ./update.sh [--check-only] [--no-backup] [--rollback]
# Requirements: .env file must exist
#
# Options:
#   --check-only    Check for updates without applying them
#   --no-backup     Skip creating backup before update
#   --rollback      Rollback to previous version
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Parse arguments
CHECK_ONLY=false
NO_BACKUP=false
ROLLBACK=false

for arg in "$@"; do
    case $arg in
        --check-only)
            CHECK_ONLY=true
            ;;
        --no-backup)
            NO_BACKUP=true
            ;;
        --rollback)
            ROLLBACK=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--check-only] [--no-backup] [--rollback]"
            exit 1
            ;;
    esac
done

# Check for .env file
if [ ! -f .env ]; then
    echo "ERROR: You need to create the .env file first"
    echo "Run: cp .env.sample .env && vim .env"
    exit 1
fi

source .env

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Rollback functionality
if [ "$ROLLBACK" = true ]; then
    echo -e "${YELLOW}Rolling back to previous version...${NC}"

    if [ ! -d "data/.update-backup" ]; then
        echo "ERROR: No backup found for rollback"
        exit 1
    fi

    echo "Stopping current containers..."
    docker compose down

    echo "Restoring previous image tags..."
    if [ -f "data/.update-backup/image-tags.txt" ]; then
        while IFS= read -r line; do
            image=$(echo "$line" | cut -d' ' -f1)
            tag=$(echo "$line" | cut -d' ' -f2)
            echo "  Pulling $image:$tag..."
            docker pull "$image:$tag" 2>/dev/null || echo "  Warning: Could not pull $image:$tag"
        done < "data/.update-backup/image-tags.txt"
    fi

    echo "Starting containers with previous versions..."
    docker compose up -d

    echo -e "${GREEN}Rollback completed!${NC}"
    exit 0
fi

# Check for available updates
echo -e "${BLUE}Checking for available updates...${NC}"
echo ""

# Save current image versions
mkdir -p data/.update-backup
docker compose images --format '{{.Repository}} {{.Tag}}' > data/.update-backup/image-tags-current.txt 2>/dev/null || true

# Pull latest to check for updates
docker compose pull --quiet 2>/dev/null || docker compose pull

# Compare versions
if [ -f "data/.update-backup/image-tags-current.txt" ]; then
    echo "Comparing versions:"
    updates_available=false

    while IFS= read -r line; do
        repo=$(echo "$line" | awk '{print $1}')
        current_tag=$(echo "$line" | awk '{print $2}')

        # Get latest tag
        latest_id=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "^$repo:" | head -1 | awk '{print $2}')
        current_id=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "^$repo:$current_tag" | awk '{print $2}')

        if [ "$latest_id" != "$current_id" ]; then
            echo -e "  ${YELLOW}⬆${NC} $repo:$current_tag (update available)"
            updates_available=true
        else
            echo -e "  ${GREEN}✓${NC} $repo:$current_tag (up to date)"
        fi
    done < "data/.update-backup/image-tags-current.txt"

    echo ""

    if [ "$updates_available" = false ]; then
        echo -e "${GREEN}All images are up to date!${NC}"
        if [ "$CHECK_ONLY" = true ]; then
            exit 0
        fi
        read -r -p "Continue anyway? [y/N] " response
        case $response in
            [yY][eE][sS]|[yY])
                ;;
            *)
                exit 0
                ;;
        esac
    fi
else
    echo "Could not compare versions (first run)"
fi

if [ "$CHECK_ONLY" = true ]; then
    echo ""
    echo -e "${BLUE}Check complete. Use './update.sh' to apply updates.${NC}"
    exit 0
fi

# Create backup before update
if [ "$NO_BACKUP" = false ]; then
    echo ""
    echo -e "${BLUE}Creating backup before update...${NC}"
    backup_dir="data/.update-backup/pre-update-$(date +%Y%m%d-%H%M%S)"

    if ./assets/backup.sh "$backup_dir" > /dev/null 2>&1; then
        echo -e "${GREEN}Backup created: $backup_dir${NC}"

        # Save current image versions for rollback
        cp data/.update-backup/image-tags-current.txt data/.update-backup/image-tags.txt
    else
        echo -e "${YELLOW}Warning: Backup failed, but continuing...${NC}"
    fi
fi

echo ""
echo "Pulling latest images..."
docker compose pull         # Get latest version of all images

echo "Recreating containers with new images..."
docker compose up -d        # Recreate containers with new images

# Update all installed stacks
echo ""
echo "Checking for installed stacks..."
if [ -x ./assets/stack.sh ]; then
    installed_stacks=$(./assets/stack.sh installed 2>/dev/null | grep -E "^\[installed\]" | awk '{print $2}' || true)

    if [ -n "$installed_stacks" ]; then
        echo "Found installed stacks:"
        echo "$installed_stacks" | while read -r stack; do
            echo "  - $stack"
        done
        echo ""

        echo "Updating installed stacks..."
        echo "$installed_stacks" | while read -r stack; do
            stack_dir="jacker-stacks"
            # Find stack directory
            stack_path=$(find "$stack_dir" -type f -name "stack.yml" | grep "/$stack/" | head -1)

            if [ -n "$stack_path" ]; then
                stack_base=$(dirname "$stack_path")
                echo "Updating stack: $stack..."

                # Check if stack has an update script
                if [ -f "$stack_base/assets/update.sh" ]; then
                    echo "  Running update script..."
                    (cd "$stack_base" && bash assets/update.sh) || echo "  Warning: Update script failed for $stack"
                else
                    # Default update: pull images and restart
                    echo "  Pulling latest images..."
                    if [ -f "$stack_base/stack.yml" ]; then
                        docker compose -f "$stack_base/stack.yml" pull 2>/dev/null || echo "  Warning: Could not pull images for $stack"
                        echo "  Restarting stack..."
                        docker compose -f "$stack_base/stack.yml" up -d 2>/dev/null || echo "  Warning: Could not restart $stack"
                    elif [ -f "$stack_base/docker-compose.yml" ]; then
                        docker compose -f "$stack_base/docker-compose.yml" pull 2>/dev/null || echo "  Warning: Could not pull images for $stack"
                        echo "  Restarting stack..."
                        docker compose -f "$stack_base/docker-compose.yml" up -d 2>/dev/null || echo "  Warning: Could not restart $stack"
                    fi
                fi
                echo "  ✓ $stack updated"
            else
                echo "  Warning: Could not find stack directory for $stack"
            fi
        done
        echo ""
    else
        echo "No installed stacks found"
    fi
else
    echo "stack.sh tool not found, skipping stack updates"
fi

echo "Cleaning up unused images..."
docker image prune -a -f    # Remove all unused images

echo ""
echo "Update completed successfully!"
echo "IMPORTANT: Reboot your system to ensure all changes take effect."
echo ""
read -r -p "Do you want to reboot now? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    sudo reboot
  ;;
  *)
    echo "Remember to reboot later."
  ;;
esac
