# Migrate ECS Service to Copilot

Migrate an ECS service from ecs-deploy to AWS Copilot.

## Arguments
- `$ARGUMENTS` - Format: `<cluster> <service>` (e.g., `getfrom api-service`)

## Instructions

You are helping migrate an ECS service to AWS Copilot. Follow these steps:

### 1. Extract Current Configuration

First, get the current task definition:

```bash
# Get current task definition ARN
TASK_DEF=$(aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].taskDefinition' --output text)

# Export full task definition
aws ecs describe-task-definition --task-definition $TASK_DEF \
  > migration/backups/<service>-taskdef.json
```

### 2. Analyze Task Definition

Read the exported JSON and extract:
- Container definitions (image, port, cpu, memory)
- Environment variables (classify as plain vs secrets)
- Volumes and mount points
- Network mode
- Task role ARN

### 3. Create Copilot Manifest

Based on the analysis, create `copilot/services/<service>/manifest.yml`:

**Service Type Selection:**
- `Load Balanced Web Service` - for services with HTTP/HTTPS endpoints
- `Backend Service` - for internal services (service discovery only)
- `Worker Service` - for queue processors without HTTP

**Manifest Template:**
```yaml
name: <service-name>
type: <service-type>

image:
  location: <ecr-uri>
  port: <container-port>

cpu: <cpu-units>
memory: <memory-mb>
count: <desired-count>

variables:
  # Non-sensitive environment variables
  LOG_LEVEL: info

secrets:
  # Sensitive values from SSM Parameter Store
  # DATABASE_PASSWORD: /copilot/<app>/<env>/secrets/DATABASE_PASSWORD

environments:
  staging:
    count: 1
  production:
    count: 2
```

### 4. Handle Secrets

For each secret identified:

1. Create SSM parameter:
```bash
aws ssm put-parameter \
  --name /copilot/<app>/<env>/secrets/<SECRET_NAME> \
  --value "<value>" \
  --type SecureString \
  --tags Key=copilot-application,Value=<app> Key=copilot-environment,Value=<env>
```

2. Reference in manifest:
```yaml
secrets:
  SECRET_NAME: /copilot/<app>/<env>/secrets/<SECRET_NAME>
```

### 5. Update Migration Status

After creating the manifest, update `CLAUDE.md` migration status table.

### 6. Output

Provide a summary of:
- What was extracted
- What manifest was created
- What secrets need to be created (with commands, NOT actual values)
- Any manual steps required
