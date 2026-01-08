#!/bin/bash
# Export ECS task definition to JSON file
# Usage: ./export-task-definition.sh <cluster> <service>

set -e

CLUSTER=$1
SERVICE=$2

if [ -z "$CLUSTER" ] || [ -z "$SERVICE" ]; then
    echo "Usage: $0 <cluster> <service>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"

mkdir -p "$BACKUP_DIR"

echo "Getting task definition for $CLUSTER/$SERVICE..."

# Get current task definition ARN
TASK_DEF_ARN=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text)

if [ "$TASK_DEF_ARN" == "None" ] || [ -z "$TASK_DEF_ARN" ]; then
    echo "Error: Could not find service $SERVICE in cluster $CLUSTER"
    exit 1
fi

echo "Task definition: $TASK_DEF_ARN"

# Export full task definition
OUTPUT_FILE="$BACKUP_DIR/${CLUSTER}-${SERVICE}-taskdef.json"

aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_ARN" \
    --query 'taskDefinition' \
    > "$OUTPUT_FILE"

echo "Exported to: $OUTPUT_FILE"

# Also extract just the environment variables
ENV_FILE="$SCRIPT_DIR/../env-configs/${CLUSTER}-${SERVICE}.env"
mkdir -p "$(dirname "$ENV_FILE")"

echo "# Environment variables for $CLUSTER/$SERVICE" > "$ENV_FILE"
echo "# Extracted from: $TASK_DEF_ARN" >> "$ENV_FILE"
echo "# Date: $(date -Iseconds)" >> "$ENV_FILE"
echo "" >> "$ENV_FILE"

# Extract env vars from each container
jq -r '.containerDefinitions[] | "# Container: \(.name)\n" + ((.environment // []) | map("\(.name)=\(.value)") | join("\n")) + "\n"' \
    "$OUTPUT_FILE" >> "$ENV_FILE"

echo "Environment variables exported to: $ENV_FILE"
