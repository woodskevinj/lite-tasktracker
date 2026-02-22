#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="LiteInfraStack"

echo "=== Querying CloudFormation stack: ${STACK_NAME} ==="

STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" \
  --output json)

get_output() {
  echo "$STACK_OUTPUTS" | jq -r --arg key "$1" '.[] | select(.OutputKey == $key) | .OutputValue'
}

CLUSTER_NAME=$(get_output "EcsClusterName")
SERVICE_NAME=$(get_output "EcsServiceName")

echo "  Cluster: ${CLUSTER_NAME}"
echo "  Service: ${SERVICE_NAME}"

echo ""
echo "=== Scaling ECS service to 0 ==="
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count 0 \
  --query "service.{Service:serviceName,Desired:desiredCount,Running:runningCount}" \
  --output table

echo ""
echo "=== Waiting for all tasks to drain and stop ==="
echo "(This may take up to 2 minutes...)"
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME"

echo ""
echo "=== ECS service stopped ==="
echo "All tasks have been drained and stopped."
echo ""
echo "Note: AWS infrastructure (VPC, RDS, ECR, ALB) is managed in lite-infra."
echo "To fully tear down all resources, run 'cdk destroy' in the lite-infra repo."
