#!/bin/bash
# List all services in an ECS cluster
# Usage: ./list-cluster-services.sh <cluster>

set -e

CLUSTER=$1

if [ -z "$CLUSTER" ]; then
    echo "Usage: $0 <cluster>"
    exit 1
fi

echo "Services in cluster: $CLUSTER"
echo "========================================"
echo ""

# Get all service ARNs
SERVICE_ARNS=$(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns' --output json)

if [ "$SERVICE_ARNS" == "[]" ]; then
    echo "No services found in cluster $CLUSTER"
    exit 0
fi

# Get details for all services
aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services $(echo "$SERVICE_ARNS" | jq -r '.[]') \
    --query 'services[*].{
        name:serviceName,
        status:status,
        desired:desiredCount,
        running:runningCount,
        taskDef:taskDefinition
    }' \
    --output table

echo ""
echo "Task Definition Details:"
echo "------------------------"

# Get task definition details for each service
for SERVICE_ARN in $(echo "$SERVICE_ARNS" | jq -r '.[]'); do
    SERVICE_NAME=$(basename "$SERVICE_ARN")

    TASK_DEF=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$SERVICE_NAME" \
        --query 'services[0].taskDefinition' \
        --output text)

    echo ""
    echo "Service: $SERVICE_NAME"
    echo "Task Definition: $TASK_DEF"

    # Get container info
    aws ecs describe-task-definition \
        --task-definition "$TASK_DEF" \
        --query 'taskDefinition.containerDefinitions[*].{name:name,image:image,cpu:cpu,memory:memory}' \
        --output table 2>/dev/null || echo "  (Could not fetch task definition details)"
done
