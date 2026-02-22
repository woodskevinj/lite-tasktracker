#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="LiteInfraStack"

echo "=== Querying CloudFormation stack: ${STACK_NAME} ==="

# Fetch all stack outputs in one call and extract needed values
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" \
  --output json)

get_output() {
  echo "$STACK_OUTPUTS" | jq -r --arg key "$1" '.[] | select(.OutputKey == $key) | .OutputValue'
}

CLUSTER_NAME=$(get_output "EcsClusterName")
SERVICE_NAME=$(get_output "EcsServiceName")
FRONTEND_ECR_URI=$(get_output "FrontendEcrUri")
BACKEND_ECR_URI=$(get_output "BackendEcrUri")
ALB_DNS=$(get_output "AlbDnsName")

echo "  Cluster:      ${CLUSTER_NAME}"
echo "  Service:      ${SERVICE_NAME}"
echo "  Frontend ECR: ${FRONTEND_ECR_URI}"
echo "  Backend ECR:  ${BACKEND_ECR_URI}"
echo "  ALB DNS:      ${ALB_DNS}"

# Derive the ECR registry host from the frontend URI (strip /repo-name)
ECR_REGISTRY="${FRONTEND_ECR_URI%%/*}"

echo ""
echo "=== Logging in to ECR ==="
aws ecr get-login-password \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo ""
echo "=== Building and pushing frontend ==="
docker build -t "${FRONTEND_ECR_URI}:latest" ./frontend
docker push "${FRONTEND_ECR_URI}:latest"

echo ""
echo "=== Building and pushing backend ==="
docker build -t "${BACKEND_ECR_URI}:latest" ./backend
docker push "${BACKEND_ECR_URI}:latest"

echo ""
echo "=== Registering new task definition revision ==="

# Get the current task definition ARN from the running service
CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --query "services[0].taskDefinition" \
  --output text)

echo "  Current task definition: ${CURRENT_TASK_DEF_ARN}"

# Fetch the current task definition and transform it:
#   - Replace frontend container image with ECR URI
#   - Replace backend container image with ECR URI and remove any placeholder command
#   - Strip fields that cannot be included when re-registering
TASK_DEF_JSON=$(aws ecs describe-task-definition \
  --task-definition "$CURRENT_TASK_DEF_ARN" \
  --query "taskDefinition")

NEW_TASK_DEF=$(echo "$TASK_DEF_JSON" | jq \
  --arg frontend_image "${FRONTEND_ECR_URI}:latest" \
  --arg backend_image "${BACKEND_ECR_URI}:latest" \
  '
  .containerDefinitions |= map(
    if .name == "frontend" then .image = $frontend_image
    elif .name == "backend" then .image = $backend_image | del(.command)
    else .
    end
  )
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
        .compatibilities, .registeredAt, .registeredBy)
  ')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "  New task definition: ${NEW_TASK_DEF_ARN}"

echo ""
echo "=== Updating ECS service ==="
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --force-new-deployment \
  --query "service.deployments[0].{Status:status,Running:runningCount,Desired:desiredCount}" \
  --output table

echo ""
echo "=== Deployment triggered successfully ==="
echo "Task definition: ${NEW_TASK_DEF_ARN}"
echo "Application URL: http://${ALB_DNS}"
echo "Monitor with:    aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --query 'services[0].deployments'"
