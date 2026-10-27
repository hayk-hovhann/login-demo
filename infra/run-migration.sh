#!/usr/bin/env bash
# Run pending Prisma migrations as a one-shot Fargate task, then report the result.
#
# Why a script and not an output: an output can only hand you a string. This
# waits for the task, surfaces the container exit code, and tails the logs — and
# it resolves everything at run time, so nothing has to be baked in: the app's
# names from Terraform's outputs, the subnets from the network stack's exports,
# the DB client group from the data layer's SSM parameter. The task wears that
# badge beside its own group from the app: the badge has no egress, so the
# app's group is what lets the task out to ECR, Secrets Manager and RDS.
#
#   ./infra/run-migration.sh
#
# The network stack name, the data layer's parameter path and the Terraform
# directory can be overridden by env var.
set -euo pipefail

NETWORK_STACK="${NETWORK_STACK:-login-demo-network}"
DATA_PARAMETER_PATH="${DATA_PARAMETER_PATH:-/login-demo/data}"
TF_DIR="${TF_DIR:-$(dirname "$0")/terraform/app}"

die() { echo "error: $*" >&2; exit 1; }

# list-exports returns empty (not an error) for a missing name, so check each one.
export_value() {
  local name="$1" value
  value=$(aws cloudformation list-exports \
            --query "Exports[?Name=='${name}'].Value" --output text)
  if [ -z "$value" ] || [ "$value" = "None" ]; then
    die "export '${name}' not found — is the stack deployed?"
  fi
  echo "$value"
}

# Unlike list-exports, a missing output is an error: terraform exits non-zero
# and prints its own message, so no empty-string check is needed.
tf_output() {
  local name="$1" value
  value=$(terraform -chdir="$TF_DIR" output -raw "$name") \
    || die "output '${name}' not found in ${TF_DIR} — has the app been applied?"
  echo "$value"
}

# One of the data layer's published outputs (infra/terraform/data/parameters.tf).
# A missing parameter is an error too: get-parameter exits non-zero with
# ParameterNotFound.
data_param() {
  local name="$1" value
  value=$(aws ssm get-parameter --name "${DATA_PARAMETER_PATH}/${name}" \
            --query Parameter.Value --output text) \
    || die "parameter '${DATA_PARAMETER_PATH}/${name}' not found — has data been applied?"
  echo "$value"
}

SUBNET_A=$(export_value "${NETWORK_STACK}-SubnetAId")
SUBNET_B=$(export_value "${NETWORK_STACK}-SubnetBId")
DB_CLIENT_SG=$(data_param db_client_security_group_id)
LOG_GROUP=$(tf_output migrate_log_group_name)
CLUSTER=$(tf_output cluster_name)
TASK_DEF=$(tf_output migrate_task_definition_family)
MIGRATE_SG=$(tf_output migrate_security_group_id)

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
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_A},${SUBNET_B}],securityGroups=[${MIGRATE_SG},${DB_CLIENT_SG}],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  die "run-task returned no task ARN"
fi
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
