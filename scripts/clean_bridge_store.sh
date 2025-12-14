#!/bin/bash
# Clean up bridge/store for full WhatsApp resync
#
# Use this when:
# - Go bridge code changes require a fresh sync
# - Database schema changes
# - WhatsApp session needs to be re-authenticated
#
# This deletes:
# - whatsapp.db (session/device state - you'll need to scan QR code again)
# - messages.db (message history)
# - Downloaded media files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE_DIR="$SCRIPT_DIR/../bridge/store"

if [ ! -d "$STORE_DIR" ]; then
    echo "Store directory does not exist: $STORE_DIR"
    echo "Nothing to clean."
    exit 0
fi

echo "This will delete ALL data in bridge/store/:"
echo "  - WhatsApp session (you'll need to scan QR code again)"
echo "  - Message history"
echo "  - Downloaded media"
echo ""
echo "Store directory: $STORE_DIR"
echo ""

# Show what will be deleted
if [ -n "$(ls -A "$STORE_DIR" 2>/dev/null)" ]; then
    echo "Contents to be deleted:"
    ls -la "$STORE_DIR"
    echo ""
else
    echo "Store directory is already empty."
    exit 0
fi

read -p "Are you sure? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Cleaning bridge/store/..."

# Delete everything in store directory
rm -rf "$STORE_DIR"/*

echo "Done. Bridge store has been cleaned."
echo ""
echo "Next steps:"
echo "  1. cd bridge && go run ."
echo "  2. Scan the QR code with your WhatsApp mobile app"
