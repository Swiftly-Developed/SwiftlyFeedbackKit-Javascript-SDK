#!/bin/bash

# Generate API documentation from OpenAPI specification
# Requires: npm install -g redoc-cli

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="$SCRIPT_DIR/../openapi/openapi.yaml"
OUTPUT_DIR="$SCRIPT_DIR/../docs"
OUTPUT_FILE="$OUTPUT_DIR/api.html"

echo "Generating API documentation..."
echo "Input: $SPEC_FILE"
echo "Output: $OUTPUT_FILE"
echo ""

if ! command -v redoc-cli &> /dev/null; then
    echo "Error: redoc-cli is not installed."
    echo "Install it with: npm install -g redoc-cli"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

redoc-cli bundle "$SPEC_FILE" \
    --output "$OUTPUT_FILE" \
    --title "FeedbackKit API Documentation" \
    --options.theme.colors.primary.main="#F7A50D" \
    --options.hideDownloadButton

echo ""
echo "Documentation generated successfully!"
echo "Open $OUTPUT_FILE in your browser to view."
