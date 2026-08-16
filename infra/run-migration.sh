#!/usr/bin/env bash
# Run pending Prisma migrations as a one-shot Fargate task, then report the result.
#
# Why a script and not a stack Output: an Output can only hand you a string. This
# waits for the task, surfaces the container exit code, and tails the logs — and
# it resolves subnet/SG ids from the stack exports at run time, so nothing has to
# be baked into the template.
#
#   ./infra/run-migration.sh
#
# Stack names can be overridden by env var if you deploy under different names.
set -euo pipefail

APP_STACK="${APP_STACK:-login-demo-app}"
NETWORK_STACK="${NETWORK_STACK:-login-demo-network}"
DATA_STACK="${DATA_STACK:-login-demo-data}"

die() { echo "error: $*" >&2; exit 1; }

# list-exports returns empty (not an error) for a missing name, so check each one.
export_value() {
  local name="$1" value
  value=$(aws cloudformation list-exports \
            --query "Exports[?Name=='${name}'].Value" --output text)
  [ -n "$value" ] && [ "$value" != "None" ] || die "export '${name}' not found — is the stack deployed?"
  echo "$value"
}

stack_output() {
  local name="$1" value
  value=$(aws cloudformation describe-stacks --stack-name "$APP_STACK" \
            --query "Stacks[0].Outputs[?OutputKey=='${name}'].OutputValue" --output text)
  [ -n "$value" ] && [ "$value" != "None" ] || die "output '${name}' not found on ${APP_STACK}"
  echo "$value"
}

SUBNET_A=$(export_value "${NETWORK_STACK}-SubnetAId")
SUBNET_B=$(export_value "${NETWORK_STACK}-SubnetBId")
DB_CLIENT_SG=$(export_value "${DATA_STACK}-DbClientSgId")
LOG_GROUP=$(stack_output MigrateLogGroupName)

CLUSTER="${APP_STACK}-Cluster"
TASK_DEF="${APP_STACK}-migrate"

echo "cluster:  ${CLUSTER}"
echo "task def: ${TASK_DEF}"
echo "subnets:  ${SUBNET_A}, ${SUBNET_B}"
echo

# assignPublicIp=ENABLED is REQUIRED: tasks run in public subnets and the VPC has
# no NAT gateway, so without it the task cannot reach ECR or Secrets Manager and
# dies with ResourceInitializationError — which reads like an IAM problem.
TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEF" \
  --launch-type FARGATE \
  --started-by manual-migrate \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_A},${SUBNET_B}],securityGroups=[${DB_CLIENT_SG}],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)

[ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ] || die "run-task returned no task ARN"
echo "task: ${TASK_ARN}"
echo "waiting for it to stop (first run pulls a ~670MB image, allow a minute)..."

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)
STOPPED_REASON=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].stoppedReason' --output text)

echo
echo "----- migration logs -----"
aws logs tail "$LOG_GROUP" --since 15m || true
echo "--------------------------"
echo

if [ "$EXIT_CODE" = "0" ]; then
  echo "migration succeeded (exit 0)"
else
  echo "migration FAILED — exit=${EXIT_CODE} reason=${STOPPED_REASON}" >&2
  exit 1
fi
