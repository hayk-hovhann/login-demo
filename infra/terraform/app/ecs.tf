# The ECS cluster: Cluster in app-ecs.yaml. The namespace the backend and
# frontend services run in. On Fargate it holds no machines, so it costs nothing
# on its own; the tasks placed in it are what bill.
#
# The name keeps CloudFormation's capital C, unlike every other name here,
# because three things find the cluster by name rather than by reference: CD's
# locate step (cd.yml:115, :233) by the case-sensitive substring
# 'login-demo-app-Cluster', skipping the deploy silently if nothing matches;
# run-migration.sh:46, which builds the exact name; and the dashboard's
# ClusterName dimension, once it is ported.
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-Cluster"
}
