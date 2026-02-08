#!/bin/bash

# Validate OpenAPI specification
# Requires: npm install -g @apidevtools/swagger-cli

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="$SCRIPT_DIR/../openapi/openapi.yaml"

echo "Validating OpenAPI specification..."
echo "File: $SPEC_FILE"
echo ""

if ! command -v swagger-cli &> /dev/null; then
    echo "Error: swagger-cli is not installed."
    echo "Install it with: npm install -g @apidevtools/swagger-cli"
    exit 1
fi

swagger-cli validate "$SPEC_FILE"

echo ""
echo "Validation successful!"
