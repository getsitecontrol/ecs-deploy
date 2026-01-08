# ECS to Copilot Migration Tools

This directory contains scripts and storage for migrating ECS services from `ecs-deploy` to AWS Copilot.

## Directory Structure

```
migration/
├── scripts/           # Helper scripts
├── backups/           # Exported task definitions (gitignored)
└── env-configs/       # Extracted environment configs (gitignored)
```

## Scripts

### `list-cluster-services.sh`
List all services in an ECS cluster with their task definitions.

```bash
./scripts/list-cluster-services.sh getfrom
```

### `export-task-definition.sh`
Export a service's task definition to JSON and extract environment variables.

```bash
./scripts/export-task-definition.sh getfrom my-service
# Creates: backups/getfrom-my-service-taskdef.json
# Creates: env-configs/getfrom-my-service.env
```

### `convert-to-copilot.sh`
Convert exported task definition JSON to a Copilot manifest YAML.

```bash
./scripts/convert-to-copilot.sh backups/getfrom-my-service-taskdef.json getfrom "Backend Service"
# Outputs manifest YAML to stdout
# Redirect to file: > ../copilot/services/my-service/manifest.yml
```

### `create-ssm-secrets.sh`
Create SSM Parameter Store secrets for Copilot.

```bash
# Create secrets file (not committed to git!)
echo "DATABASE_PASSWORD=mypassword" > secrets.txt
echo "API_KEY=abc123" >> secrets.txt

# Create SSM parameters
./scripts/create-ssm-secrets.sh getfrom staging secrets.txt
```

## Typical Migration Workflow

1. **List services to migrate:**
   ```bash
   ./scripts/list-cluster-services.sh getfrom
   ```

2. **Export task definition:**
   ```bash
   ./scripts/export-task-definition.sh getfrom api-service
   ```

3. **Review and classify environment variables:**
   - Edit `env-configs/getfrom-api-service.env`
   - Separate secrets from plain variables

4. **Generate Copilot manifest:**
   ```bash
   mkdir -p ../copilot/services/api-service
   ./scripts/convert-to-copilot.sh backups/getfrom-api-service-taskdef.json getfrom "Load Balanced Web Service" \
     > ../copilot/services/api-service/manifest.yml
   ```

5. **Create secrets in SSM:**
   ```bash
   # Create a file with ONLY secrets (not committed!)
   ./scripts/create-ssm-secrets.sh getfrom staging secrets.txt
   ```

6. **Review and adjust manifest:**
   - Edit `copilot/services/api-service/manifest.yml`
   - Add environment-specific overrides
   - Configure health checks, scaling, etc.

7. **Deploy with Copilot:**
   ```bash
   copilot svc deploy --name api-service --env staging
   ```

## Security Notes

- `backups/` and `env-configs/` directories are gitignored
- Never commit files containing secrets
- Use SSM Parameter Store for all sensitive values
- Delete local secrets files after creating SSM parameters
