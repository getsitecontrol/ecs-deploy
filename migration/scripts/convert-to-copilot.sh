#!/bin/bash
# Convert exported task definition JSON to Copilot manifest YAML
# Usage: ./convert-to-copilot.sh <task-def.json> <app-name> <service-type>

set -e

TASK_DEF_FILE=$1
APP_NAME=${2:-getfrom}
SERVICE_TYPE=${3:-"Backend Service"}

if [ -z "$TASK_DEF_FILE" ]; then
    echo "Usage: $0 <task-def.json> [app-name] [service-type]"
    echo "Service types: 'Load Balanced Web Service', 'Backend Service', 'Worker Service'"
    exit 1
fi

if [ ! -f "$TASK_DEF_FILE" ]; then
    echo "Error: File not found: $TASK_DEF_FILE"
    exit 1
fi

# Extract values from task definition
FAMILY=$(jq -r '.family' "$TASK_DEF_FILE")
CPU=$(jq -r '.cpu // "256"' "$TASK_DEF_FILE")
MEMORY=$(jq -r '.memory // "512"' "$TASK_DEF_FILE")

# Get first container (main container)
CONTAINER=$(jq '.containerDefinitions[0]' "$TASK_DEF_FILE")
CONTAINER_NAME=$(echo "$CONTAINER" | jq -r '.name')
IMAGE=$(echo "$CONTAINER" | jq -r '.image')
PORT=$(echo "$CONTAINER" | jq -r '.portMappings[0].containerPort // 8080')

echo "# Copilot manifest for $FAMILY"
echo "# Generated from: $TASK_DEF_FILE"
echo "# Date: $(date -Iseconds)"
echo ""
echo "name: $FAMILY"
echo "type: $SERVICE_TYPE"
echo ""
echo "image:"
echo "  location: $IMAGE"
echo "  port: $PORT"
echo ""
echo "cpu: $CPU"
echo "memory: $MEMORY"
echo "count: 1"
echo ""

# Extract plain environment variables
echo "variables:"
jq -r '.containerDefinitions[0].environment // [] | .[] | "  \(.name): \"\(.value)\""' "$TASK_DEF_FILE" | \
    grep -v -E '(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|PRIVATE)' || echo "  # No plain variables found"

echo ""

# Extract secrets (variables that look sensitive)
echo "secrets:"
echo "  # TODO: Create these secrets in SSM Parameter Store"
jq -r '.containerDefinitions[0].environment // [] | .[] | .name' "$TASK_DEF_FILE" | \
    grep -E '(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|PRIVATE)' | \
    while read -r name; do
        echo "  # $name: /copilot/$APP_NAME/\${COPILOT_ENVIRONMENT_NAME}/secrets/$name"
    done

# Check for existing secrets references
EXISTING_SECRETS=$(jq -r '.containerDefinitions[0].secrets // [] | .[] | "  \(.name): \(.valueFrom)"' "$TASK_DEF_FILE")
if [ -n "$EXISTING_SECRETS" ]; then
    echo ""
    echo "  # Existing secrets from task definition:"
    echo "$EXISTING_SECRETS"
fi

echo ""
echo "environments:"
echo "  staging:"
echo "    count: 1"
echo "  production:"
echo "    count: 2"

# Check for additional containers
CONTAINER_COUNT=$(jq '.containerDefinitions | length' "$TASK_DEF_FILE")
if [ "$CONTAINER_COUNT" -gt 1 ]; then
    echo ""
    echo "# WARNING: Task definition has $CONTAINER_COUNT containers"
    echo "# Additional containers may need sidecars configuration:"
    echo "# sidecars:"
    jq -r '.containerDefinitions[1:] | .[] | "#   \(.name):\n#     image: \(.image)"' "$TASK_DEF_FILE"
fi
