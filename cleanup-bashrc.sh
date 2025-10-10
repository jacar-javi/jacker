#!/usr/bin/env bash
#
# Script: cleanup-bashrc.sh
# Description: Remove duplicate Jacker setup.sh entries from ~/.bashrc
# Usage: ./cleanup-bashrc.sh
#
# This script fixes the issue where multiple install attempts added
# multiple entries to ~/.bashrc, causing setup.sh to run many times on login

set -euo pipefail

echo "=== Jacker bashrc Cleanup Utility ==="
echo ""

if [ ! -f ~/.bashrc ]; then
    echo "No ~/.bashrc file found. Nothing to clean up."
    exit 0
fi

# Count current jacker setup entries
CURRENT_COUNT=$(grep -c "jacker.*setup\.sh" ~/.bashrc 2>/dev/null || echo "0")

if [ "$CURRENT_COUNT" -eq "0" ]; then
    echo "✓ No Jacker setup entries found in ~/.bashrc"
    echo "  Your bashrc is clean!"
    exit 0
fi

echo "Found $CURRENT_COUNT Jacker setup.sh entry/entries in ~/.bashrc"
echo ""

# Show the entries that will be removed
echo "Entries to be removed:"
echo "----------------------------------------"
grep "jacker.*setup\.sh" ~/.bashrc | sed 's/^/  /'
echo "----------------------------------------"
echo ""

# Ask for confirmation
read -r -p "Remove these entries? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        # Backup the original bashrc
        BACKUP_FILE=~/.bashrc.backup.$(date +%Y%m%d-%H%M%S)
        cp ~/.bashrc "$BACKUP_FILE"
        echo "✓ Backup created: $BACKUP_FILE"

        # Remove all jacker setup entries
        grep -v "jacker.*setup\.sh" ~/.bashrc > ~/.bashrc.tmp 2>/dev/null || cp ~/.bashrc ~/.bashrc.tmp
        mv ~/.bashrc.tmp ~/.bashrc

        # Verify cleanup
        REMAINING_COUNT=$(grep -c "jacker.*setup\.sh" ~/.bashrc 2>/dev/null || echo "0")

        if [ "$REMAINING_COUNT" -eq "0" ]; then
            echo "✓ Successfully removed all Jacker setup entries"
            echo ""
            echo "Changes:"
            echo "  - Removed: $CURRENT_COUNT entries"
            echo "  - Backup: $BACKUP_FILE"
            echo ""
            echo "Note: Changes will take effect on next login or run: source ~/.bashrc"
        else
            echo "⚠️  Warning: $REMAINING_COUNT entries still remain"
            echo "  Please check manually: grep jacker ~/.bashrc"
        fi
        ;;
    *)
        echo "Cleanup cancelled. No changes made."
        exit 0
        ;;
esac

# Check if .FIRST_ROUND marker exists
cd "$(dirname "$0")"
if [ -f ".FIRST_ROUND" ]; then
    echo ""
    echo "=== Found .FIRST_ROUND marker ==="
    echo ""
    echo "The setup process was interrupted. You have two options:"
    echo ""
    echo "1) Continue the interrupted setup after reboot"
    echo "   - Keep the marker file"
    echo "   - On next login, setup will continue from second round"
    echo ""
    echo "2) Start fresh installation"
    echo "   - Remove the marker file"
    echo "   - Run 'make install' again"
    echo ""
    read -r -p "Remove .FIRST_ROUND marker? [y/N] " response
    case $response in
        [yY][eE][sS]|[yY])
            rm .FIRST_ROUND
            echo "✓ Marker removed. You can now run 'make install' for a fresh setup."
            ;;
        *)
            echo "Marker kept. Setup will continue on next login."
            ;;
    esac
fi

echo ""
echo "=== Cleanup Complete ==="
echo ""
