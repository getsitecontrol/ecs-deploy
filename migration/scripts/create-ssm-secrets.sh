#!/bin/bash
# Create SSM Parameter Store secrets for Copilot
# Usage: ./create-ssm-secrets.sh <app> <env> <secrets-file>
#
# Secrets file format (one per line):
# SECRET_NAME=secret_value

set -e

APP_NAME=$1
ENV_NAME=$2
SECRETS_FILE=$3

if [ -z "$APP_NAME" ] || [ -z "$ENV_NAME" ] || [ -z "$SECRETS_FILE" ]; then
    echo "Usage: $0 <app-name> <env-name> <secrets-file>"
    echo ""
    echo "Example: $0 getfrom staging secrets.txt"
    echo ""
    echo "Secrets file format:"
    echo "  DATABASE_PASSWORD=mypassword"
    echo "  API_KEY=abc123"
    exit 1
fi

if [ ! -f "$SECRETS_FILE" ]; then
    echo "Error: Secrets file not found: $SECRETS_FILE"
    exit 1
fi

echo "Creating SSM secrets for $APP_NAME/$ENV_NAME..."
echo ""

while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ $key =~ ^#.*$ ]] && continue
    [[ -z $key ]] && continue

    PARAM_NAME="/copilot/$APP_NAME/$ENV_NAME/secrets/$key"

    echo "Creating: $PARAM_NAME"

    aws ssm put-parameter \
        --name "$PARAM_NAME" \
        --value "$value" \
        --type SecureString \
        --tags "Key=copilot-application,Value=$APP_NAME" "Key=copilot-environment,Value=$ENV_NAME" \
        --overwrite \
        2>/dev/null || {
            # If tags fail (parameter exists), just update value
            aws ssm put-parameter \
                --name "$PARAM_NAME" \
                --value "$value" \
                --type SecureString \
                --overwrite
        }

    echo "  Created: $PARAM_NAME"
done < "$SECRETS_FILE"

echo ""
echo "Done! Created secrets in SSM Parameter Store."
echo ""
echo "Reference them in your Copilot manifest:"
echo "secrets:"
while IFS='=' read -r key value; do
    [[ $key =~ ^#.*$ ]] && continue
    [[ -z $key ]] && continue
    echo "  $key: /copilot/$APP_NAME/$ENV_NAME/secrets/$key"
done < "$SECRETS_FILE"
