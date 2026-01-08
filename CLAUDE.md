# Claude Code Instructions for ECS to Copilot Migration

## Project Overview

This project is migrating from custom `ecs-deploy` Python CLI tool to **AWS Copilot CLI** for ECS deployments.

**Current State:** Legacy ecs-deploy tool (Python/Click)
**Target State:** AWS Copilot with declarative YAML manifests

## Migration Status

| Cluster | Environment | Status |
|---------|-------------|--------|
| getfrom | staging | 🔄 In Progress |
| getfrom | production | ⏳ Pending |
| ... | ... | ⏳ Pending |

## Directory Structure

```
ecs-deploy/
├── CLAUDE.md                    # This file
├── MIGRATION_TO_COPILOT.md      # Detailed migration plan
├── copilot/                     # AWS Copilot configuration
│   ├── .workspace               # Copilot workspace marker
│   ├── environments/            # Environment definitions
│   │   └── staging/
│   │       └── manifest.yml
│   └── services/                # Service manifests (to be created)
│       └── <service-name>/
│           └── manifest.yml
├── migration/                   # Migration helpers
│   ├── scripts/                 # Helper scripts
│   ├── backups/                 # Task definition backups
│   └── env-configs/             # Extracted env configurations
└── ecs_deploy/                  # Legacy tool (reference only)
```

## Key Commands for Migration

### Export Current Task Definition
```bash
aws ecs describe-task-definition --task-definition <name> \
  --query 'taskDefinition' > migration/backups/<name>.json
```

### Extract Environment Variables
```bash
./migration/scripts/extract-env.sh <cluster> <service> > migration/env-configs/<service>.env
```

### Convert to Copilot Manifest
```bash
./migration/scripts/convert-to-copilot.sh migration/backups/<name>.json
```

### Create SSM Secrets
```bash
./migration/scripts/create-secrets.sh <app> <env> migration/env-configs/<service>.env
```

## Workflow for Migrating a Service

### Step 1: Backup Current State
```bash
# Get current task definition
aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].taskDefinition' --output text

# Export full task definition
aws ecs describe-task-definition --task-definition <task-def-arn> \
  > migration/backups/<service>-taskdef.json
```

### Step 2: Extract and Classify Environment Variables

Review the task definition and separate:
- **Plain variables** → `variables:` section in manifest
- **Secrets** (passwords, keys, tokens) → SSM Parameter Store + `secrets:` section

### Step 3: Create Copilot Manifest

Create `copilot/services/<service-name>/manifest.yml`:

```yaml
name: <service-name>
type: Load Balanced Web Service  # or Backend Service, Worker Service

image:
  location: <ecr-image-uri>
  port: <port>

cpu: <cpu>
memory: <memory>
count: <desired-count>

variables:
  VAR_NAME: value

secrets:
  SECRET_NAME: /copilot/<app>/<env>/secrets/<secret-name>

environments:
  staging:
    count: 1
    variables:
      ENV_SPECIFIC: value
```

### Step 4: Create SSM Secrets

```bash
aws ssm put-parameter \
  --name /copilot/<app>/<env>/secrets/<secret-name> \
  --value "<secret-value>" \
  --type SecureString \
  --tags Key=copilot-application,Value=<app> Key=copilot-environment,Value=<env>
```

### Step 5: Test Deploy (Staging First!)

```bash
copilot svc deploy --name <service> --env staging
```

## Important Notes

1. **Always start with staging environment** before touching production
2. **Backup everything** before making changes
3. **Never commit secrets** to git - use SSM Parameter Store
4. **Test thoroughly** after each migration

## Environment Variables Naming Convention

For SSM secrets, use this pattern:
```
/copilot/<application>/<environment>/secrets/<SECRET_NAME>
```

Example:
```
/copilot/getfrom/staging/secrets/DATABASE_PASSWORD
/copilot/getfrom/production/secrets/DATABASE_PASSWORD
```

## Useful AWS CLI Commands

```bash
# List all task definitions for a family
aws ecs list-task-definitions --family-prefix <family>

# Get service details
aws ecs describe-services --cluster <cluster> --services <service>

# List SSM parameters
aws ssm describe-parameters --filters "Key=Path,Values=/copilot/"

# Get SSM parameter value
aws ssm get-parameter --name <param-name> --with-decryption
```

## Rollback Procedure

If something goes wrong after Copilot deployment:

```bash
# Copilot rollback
copilot svc rollback --name <service> --env <env>

# Or revert to old task definition using ecs-deploy
ecs deploy <cluster> <service> --task <old-task-def-arn>
```

## Questions to Ask Before Migrating Each Service

1. What type of service is it? (Load Balanced, Backend, Worker)
2. Does it need public access or internal only?
3. What secrets does it use?
4. Are there any custom IAM roles?
5. Does it use volumes/storage?
6. What health check path does it use?
