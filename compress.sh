#!/bin/bash

# InventoryManager CurseForge Package Script
# Creates a clean zip file ready for CurseForge upload

# Get the addon name from the directory
ADDON_NAME="InventoryManager"
OUTPUT_FILE="${ADDON_NAME}.zip"

# Check if zip is installed, if not try to install it
if ! command -v zip &> /dev/null; then
    echo "zip command not found. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zip unzip
    elif command -v yum &> /dev/null; then
        sudo yum install -y zip unzip
    else
        echo "Error: Could not install zip. Please install it manually:"
        echo "  sudo apt-get install zip unzip"
        exit 1
    fi
fi

# Remove old zip if it exists
if [ -f "$OUTPUT_FILE" ]; then
    rm "$OUTPUT_FILE"
    echo "Removed old $OUTPUT_FILE"
fi

# Create zip with only necessary files
# Exclude: git files, readme, scripts, and other development files
zip -r "$OUTPUT_FILE" . \
    -x "*.git*" \
    -x "*.sh" \
    -x "README.md" \
    -x "*.zip" \
    -x "*.code-workspace" \
    -x ".vscode/*" \
    -x ".idea/*" \
    -x "*.bak" \
    -x "*~"

echo ""
echo "✓ Package created: $OUTPUT_FILE"
echo "✓ Ready to upload to CurseForge!"
echo ""

# Show what's included
echo "Contents:"
unzip -l "$OUTPUT_FILE"
