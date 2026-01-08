# Migration Plan: ecs-deploy → AWS Copilot CLI

## Executive Summary

This document outlines the migration strategy from the custom `ecs-deploy` CLI tool to AWS Copilot CLI for ECS deployments.

**Key Challenge:** AWS Copilot cannot directly import existing ECS services. Migration requires recreating services through Copilot manifests.

**Migration Strategy:** Gradual, service-by-service migration with parallel operation period.

---

## Current State Analysis

### ecs-deploy Tool Capabilities

| Feature | Implementation |
|---------|---------------|
| Deploy new image/tag | `ecs deploy cluster service --tag v1.2.3` |
| Environment variables | `-e container_name VAR_NAME value` (CLI flags only) |
| Scale services | `ecs scale cluster service 5` |
| Run one-off tasks | `ecs run cluster task-def` |
| Rollback | `--rollback` flag |
| New Relic integration | `--newrelic-apikey` |

### Current Limitations
- No declarative configuration (imperative CLI only)
- No .env file support - all vars via CLI flags
- Environment variables format: `(container, name, value)` tuples
- Task definitions stored only in AWS (no local source of truth)

---

## AWS Copilot Overview

### Key Differences

| Aspect | ecs-deploy | AWS Copilot |
|--------|------------|-------------|
| Configuration | CLI flags | YAML manifests |
| State | AWS ECS only | Git + AWS |
| Environments | Manual | Built-in (dev/staging/prod) |
| Secrets | Not supported | SSM Parameter Store / Secrets Manager |
| CI/CD | External | Built-in pipelines |
| Service Discovery | Manual | Automatic |

### Copilot Manifest Structure

```yaml
# copilot/api/manifest.yml
name: api
type: Load Balanced Web Service

image:
  build: ./Dockerfile
  port: 8080

cpu: 256
memory: 512
count: 2

variables:
  LOG_LEVEL: info
  APP_ENV: production

secrets:
  DATABASE_URL: /myapp/prod/secrets/database_url
  API_KEY: /myapp/prod/secrets/api_key

environments:
  staging:
    count: 1
    variables:
      APP_ENV: staging
    secrets:
      DATABASE_URL: /myapp/staging/secrets/database_url
```

---

## Migration Plan

### Phase 0: Preparation (Prerequisites)

#### 0.1 Install AWS Copilot CLI
```bash
# macOS
brew install aws/tap/copilot-cli

# Linux
curl -Lo copilot https://github.com/aws/copilot-cli/releases/latest/download/copilot-linux
chmod +x copilot
sudo mv copilot /usr/local/bin/copilot
```

#### 0.2 Inventory Current Services

Create inventory of all ECS services to migrate:

```bash
# List all clusters
aws ecs list-clusters

# For each cluster, list services
aws ecs list-services --cluster <cluster-name>

# Export task definitions
aws ecs describe-task-definition --task-definition <task-def> > task-def-backup.json
```

#### 0.3 Export Environment Variables

For each service, extract current environment variables:

```bash
# Get current task definition
aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].taskDefinition' --output text

# Extract env vars from task definition
aws ecs describe-task-definition --task-definition <task-def-arn> \
  --query 'taskDefinition.containerDefinitions[*].{name:name,environment:environment}' \
  > env-vars-backup.json
```

---

### Phase 1: Environment Variables Migration

This is the **most critical phase** - migrating your .env configs.

#### 1.1 Current Format Analysis

Your current ecs-deploy usage:
```bash
ecs deploy cluster service \
  -e container DB_HOST db.example.com \
  -e container DB_PORT 5432 \
  -e container API_KEY secret123
```

#### 1.2 Migration Strategy for Env Vars

**Option A: Plain Variables (non-sensitive)**

Convert to Copilot manifest `variables` section:

```yaml
# copilot/myservice/manifest.yml
variables:
  DB_HOST: db.example.com
  DB_PORT: "5432"
  LOG_LEVEL: info
  NODE_ENV: production
```

**Option B: Secrets (sensitive data)**

1. Create SSM parameters:
```bash
# Create secret with proper Copilot tags
aws ssm put-parameter \
  --name /myapp/prod/secrets/DB_PASSWORD \
  --value "supersecret" \
  --type SecureString \
  --tags Key=copilot-application,Value=myapp Key=copilot-environment,Value=prod
```

2. Reference in manifest:
```yaml
secrets:
  DB_PASSWORD: /myapp/prod/secrets/DB_PASSWORD
  API_KEY: /myapp/prod/secrets/API_KEY
```

**Option C: Use `copilot secret init` (recommended)**
```bash
# Interactive secret creation
copilot secret init

# This creates SSM parameters with correct naming:
# /copilot/<app>/<env>/secrets/<secret-name>
```

#### 1.3 Migration Script for .env Files

Create a helper script to convert .env files to Copilot format:

```bash
#!/bin/bash
# convert-env-to-copilot.sh
# Usage: ./convert-env-to-copilot.sh .env.production myapp prod

ENV_FILE=$1
APP_NAME=$2
ENV_NAME=$3

echo "variables:"
while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ $key =~ ^#.*$ ]] && continue
  [[ -z $key ]] && continue

  # Check if it looks like a secret
  if [[ $key =~ (PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL) ]]; then
    echo "  # MOVE TO SECRETS: $key"
  else
    echo "  $key: \"$value\""
  fi
done < "$ENV_FILE"

echo ""
echo "secrets:"
while IFS='=' read -r key value; do
  [[ $key =~ ^#.*$ ]] && continue
  [[ -z $key ]] && continue

  if [[ $key =~ (PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL) ]]; then
    echo "  $key: /$APP_NAME/$ENV_NAME/secrets/$key"
    echo "  # Run: aws ssm put-parameter --name /$APP_NAME/$ENV_NAME/secrets/$key --value \"$value\" --type SecureString --tags Key=copilot-application,Value=$APP_NAME Key=copilot-environment,Value=$ENV_NAME"
  fi
done < "$ENV_FILE"
```

#### 1.4 Environment-Specific Variables

Map your different .env files to Copilot environments:

```
.env.development  →  copilot/environments/dev/
.env.staging      →  copilot/environments/staging/
.env.production   →  copilot/environments/prod/
```

Manifest with environment overrides:
```yaml
# Base variables (all environments)
variables:
  LOG_LEVEL: info

# Environment-specific overrides
environments:
  dev:
    variables:
      LOG_LEVEL: debug
      DB_HOST: dev-db.internal
    secrets:
      DB_PASSWORD: /myapp/dev/secrets/DB_PASSWORD

  staging:
    variables:
      DB_HOST: staging-db.internal
    secrets:
      DB_PASSWORD: /myapp/staging/secrets/DB_PASSWORD

  prod:
    variables:
      DB_HOST: prod-db.internal
    secrets:
      DB_PASSWORD: /myapp/prod/secrets/DB_PASSWORD
```

---

### Phase 2: Task Definition Migration

#### 2.1 Extract Current Task Definition

```bash
aws ecs describe-task-definition \
  --task-definition my-service:latest \
  --query 'taskDefinition' > current-taskdef.json
```

#### 2.2 Map Fields to Copilot Manifest

| Task Definition Field | Copilot Manifest |
|----------------------|------------------|
| `cpu` | `cpu: 256` |
| `memory` | `memory: 512` |
| `containerDefinitions[].image` | `image.location` or `image.build` |
| `containerDefinitions[].portMappings` | `image.port` |
| `containerDefinitions[].environment` | `variables` |
| `containerDefinitions[].secrets` | `secrets` |
| `containerDefinitions[].command` | `command` |
| `containerDefinitions[].entryPoint` | `entrypoint` |
| `networkMode` | `network.vpc` |
| `volumes` | `storage.volumes` |
| `taskRoleArn` | `taskdef_overrides` |

#### 2.3 Example Conversion

**Current Task Definition:**
```json
{
  "family": "my-api",
  "cpu": "512",
  "memory": "1024",
  "networkMode": "awsvpc",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "123456789.dkr.ecr.eu-central-1.amazonaws.com/my-api:v1.2.3",
      "portMappings": [{"containerPort": 8080}],
      "environment": [
        {"name": "NODE_ENV", "value": "production"},
        {"name": "LOG_LEVEL", "value": "info"}
      ],
      "secrets": [
        {"name": "DB_PASSWORD", "valueFrom": "arn:aws:ssm:..."}
      ]
    }
  ],
  "taskRoleArn": "arn:aws:iam::123456789:role/my-task-role"
}
```

**Copilot Manifest:**
```yaml
name: my-api
type: Load Balanced Web Service

image:
  location: 123456789.dkr.ecr.eu-central-1.amazonaws.com/my-api
  port: 8080

cpu: 512
memory: 1024

variables:
  NODE_ENV: production
  LOG_LEVEL: info

secrets:
  DB_PASSWORD: /myapp/prod/secrets/DB_PASSWORD

# For custom task role, use taskdef_overrides
taskdef_overrides:
  - path: TaskRoleArn
    value: arn:aws:iam::123456789:role/my-task-role
```

#### 2.4 Advanced Task Definition Overrides

For fields not directly supported in manifest, use `taskdef_overrides`:

```yaml
taskdef_overrides:
  # Custom task role
  - path: TaskRoleArn
    value: arn:aws:iam::123456789:role/custom-role

  # Ulimits
  - path: ContainerDefinitions[0].Ulimits
    value:
      - Name: nofile
        SoftLimit: 65536
        HardLimit: 65536

  # Custom log configuration
  - path: ContainerDefinitions[0].LogConfiguration.Options.awslogs-datetime-format
    value: "%Y-%m-%d %H:%M:%S"
```

---

### Phase 3: Service-by-Service Migration

#### 3.1 Initialize Copilot Application

```bash
# Initialize new Copilot application
copilot app init myapp

# Create environments
copilot env init --name dev --profile aws-dev --default-config
copilot env init --name staging --profile aws-staging --default-config
copilot env init --name prod --profile aws-prod --default-config
```

#### 3.2 Create Service Manifests

For each service:

```bash
# Option 1: New service from Dockerfile
copilot svc init --name api --svc-type "Load Balanced Web Service"

# Option 2: Service from existing image
copilot svc init --name api --svc-type "Load Balanced Web Service" \
  --image 123456789.dkr.ecr.region.amazonaws.com/my-api
```

#### 3.3 Configure Manifest

Edit `copilot/api/manifest.yml` with all variables and settings from Phase 1-2.

#### 3.4 Deploy and Test

```bash
# Deploy to dev first
copilot svc deploy --name api --env dev

# Verify
copilot svc status --name api --env dev
copilot svc logs --name api --env dev --follow

# Deploy to staging
copilot svc deploy --name api --env staging

# Finally, production
copilot svc deploy --name api --env prod
```

---

### Phase 4: CI/CD Pipeline Setup

#### 4.1 Create Copilot Pipeline

```bash
copilot pipeline init --name main-pipeline \
  --environments "dev,staging,prod" \
  --git-branch main
```

This creates:
- `copilot/pipelines/main-pipeline/manifest.yml`
- `copilot/pipelines/main-pipeline/buildspec.yml`

#### 4.2 Pipeline Manifest Example

```yaml
# copilot/pipelines/main-pipeline/manifest.yml
name: main-pipeline
version: 1

source:
  provider: GitHub
  properties:
    branch: main
    repository: https://github.com/myorg/myrepo

stages:
  - name: dev
    test_commands:
      - echo "Running tests..."
      - npm test

  - name: staging
    requires_approval: false

  - name: prod
    requires_approval: true
```

---

### Phase 5: Decommission ecs-deploy

#### 5.1 Parallel Operation Period

Run both systems in parallel for 2-4 weeks:
- Copilot for new deployments
- ecs-deploy as fallback

#### 5.2 Verification Checklist

For each migrated service:
- [ ] All environment variables present
- [ ] Secrets accessible
- [ ] Health checks passing
- [ ] Logs flowing correctly
- [ ] Metrics in CloudWatch
- [ ] Auto-scaling working
- [ ] Rollback tested

#### 5.3 Remove ecs-deploy

Once all services migrated and verified:
```bash
# Archive the old tool
pip uninstall ecs-deploy

# Update CI/CD scripts to remove ecs-deploy references
```

---

## Command Mapping Reference

| ecs-deploy Command | Copilot Equivalent |
|-------------------|-------------------|
| `ecs deploy cluster service --tag v1` | `copilot svc deploy --tag v1` |
| `ecs deploy ... -e container VAR val` | Edit manifest `variables:` + redeploy |
| `ecs scale cluster service 5` | Edit manifest `count: 5` + redeploy |
| `ecs run cluster task` | `copilot task run --command "..."` |
| `--rollback` | `copilot svc rollback` |
| `--newrelic-apikey` | Use Copilot hooks or separate integration |

---

## Troubleshooting

### Issue: Service Discovery Changed

Copilot uses different naming conventions for service discovery:
- Old: Manual configuration
- New: `<service>.<env>.<app>.local`

**Solution:** Update any hardcoded service URLs to use new DNS names.

### Issue: IAM Roles Different

Copilot creates its own IAM roles.

**Solution:** Use `taskdef_overrides` to specify existing roles, or migrate permissions to Copilot-managed roles.

### Issue: VPC Configuration

Copilot may create new VPCs by default.

**Solution:** Use `copilot env init --import-vpc-id` to use existing VPC.

```bash
copilot env init --name prod \
  --import-vpc-id vpc-0123456789 \
  --import-public-subnets subnet-111,subnet-222 \
  --import-private-subnets subnet-333,subnet-444
```

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 0: Preparation | Inventory + backups |
| Phase 1: Env Vars | Per-service migration |
| Phase 2: Task Defs | Manifest creation |
| Phase 3: Migration | Deploy + verify per service |
| Phase 4: CI/CD | Pipeline setup |
| Phase 5: Cleanup | Decommission old tool |

---

## Resources

- [AWS Copilot CLI Documentation](https://aws.github.io/copilot-cli/)
- [Copilot Environment Variables](https://aws.github.io/copilot-cli/docs/developing/environment-variables/)
- [Copilot Secrets](https://aws.github.io/copilot-cli/docs/developing/secrets/)
- [Task Definition Overrides](https://aws.github.io/copilot-cli/docs/developing/overrides/taskdef-overrides/)
- [Copilot GitHub](https://github.com/aws/copilot-cli)
