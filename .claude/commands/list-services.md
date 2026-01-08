# List ECS Services for Migration

List all ECS services in a cluster that need to be migrated.

## Arguments
- `$ARGUMENTS` - Cluster name (e.g., `getfrom`)

## Instructions

List all services in the specified ECS cluster and show their migration status.

### 1. Get Services List

```bash
aws ecs list-services --cluster <cluster> --query 'serviceArns[*]' --output text
```

### 2. Get Details for Each Service

For each service, retrieve:
- Service name
- Current task definition
- Desired count
- Running count

```bash
aws ecs describe-services --cluster <cluster> --services <service-arns> \
  --query 'services[*].{name:serviceName,taskDef:taskDefinition,desired:desiredCount,running:runningCount}'
```

### 3. Check Migration Status

Check if a Copilot manifest already exists in `copilot/services/<service-name>/manifest.yml`

### 4. Output Table

Present results as a table:

| Service | Task Definition | Count | Migration Status |
|---------|-----------------|-------|------------------|
| api | api:42 | 2 | ✅ Migrated |
| worker | worker:15 | 1 | 🔄 In Progress |
| scheduler | scheduler:8 | 1 | ⏳ Pending |

### 5. Recommendations

Suggest which service to migrate next based on:
- Lower complexity first (fewer env vars, simpler config)
- Less critical services first (staging before production)
