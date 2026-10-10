# CloudWatch log groups: BackendLogGroup, FrontendLogGroup and MigrateLogGroup
# in app-ecs.yaml. Where each task's stdout and stderr land. Free while empty;
# stored volume is what bills, and 7-day retention keeps it small.
#
# They must exist before any task starts: the execution role's managed policy
# can write log streams into a group but cannot create one. Destroy deletes
# them, logs included: the DeletionPolicy: Delete of the CloudFormation version.
#
# One block, three copies, each addressed by its key:
# aws_cloudwatch_log_group.ecs["backend"]. Unlike count's [0], [1], [2], a key
# never shifts, so removing one group never touches the other two.
resource "aws_cloudwatch_log_group" "ecs" {
  for_each = toset(["backend", "frontend", "migrate"])

  # /ecs/<task-definition family>, the console's default. CloudFormation left
  # these unpinned, with a random suffix; the only thing that finds one by name
  # is run-migration.sh, through the migrate_log_group_name output.
  name              = "/ecs/${var.app_name}-${each.key}"
  retention_in_days = 7
}
