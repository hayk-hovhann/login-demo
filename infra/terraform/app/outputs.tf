# URL in app-ecs.yaml. Scheme from the listener shape, host from the ALB. Under
# the domain certificate the browser address is the per-session app CNAME
# instead: the ALB's own name isn't on that cert, so a browser would warn.
output "url" {
  description = "App URL: frontend at /, backend at /api/*."
  value       = "${local.tls ? "https" : "http"}://${aws_lb.main.dns_name}"
}

# MigrateTaskDefinitionFamily in app-ecs.yaml: what run-migration.sh passes to
# run-task.
output "migrate_task_definition_family" {
  description = "Family of the one-shot Prisma migration task. Run it with ./infra/run-migration.sh."
  value       = aws_ecs_task_definition.migrate.family
}

# Not in app-ecs.yaml, where run-migration.sh built the cluster's name from the
# stack's. Read instead, like everything else the script needs from here.
output "cluster_name" {
  description = "ECS cluster the services and the migration task run in."
  value       = aws_ecs_cluster.main.name
}

# RedisClientSgId in app-ecs.yaml, minus the Export: Terraform cannot create
# CloudFormation exports, so bastion.yaml takes this ID as its RedisClientSgId
# parameter instead.
output "redis_client_security_group_id" {
  description = "Attach to anything that needs Redis on 6379 (the bastion, for GUI tunneling)."
  value       = aws_security_group.redis_client.id
}

# RedisEndpoint in app-ecs.yaml. The backend's REDIS_URL is redis://<this>.
output "redis_endpoint" {
  description = "host:port of the Redis primary."
  value       = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

# SessionSecretArn in app-ecs.yaml. The backend task definition hands ECS this
# ARN to inject as SESSION_SECRET, and the execution role must be allowed to
# read it.
output "session_secret_arn" {
  description = "Secrets Manager ARN holding the express-session signing key."
  value       = aws_secretsmanager_secret.session.arn
}

# LoadBalancerDnsName in app-ecs.yaml: the bare hostname, no scheme. The
# per-session app CNAME points at it, and make-cert.sh:115 reads it as the
# name its certificate must cover; at cutover that switches to
# terraform output -raw.
output "alb_dns_name" {
  description = "ALB DNS name, with no scheme. The app CNAME's target."
  value       = aws_lb.main.dns_name
}

# DashboardURL in app-ecs.yaml: one click from the terminal to the dashboard.
output "dashboard_url" {
  description = "CloudWatch console link to this session's dashboard."
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# MigrateLogGroupName in app-ecs.yaml. run-migration.sh reads it to tail the
# migration's logs.
output "migrate_log_group_name" {
  description = "CloudWatch log group the one-shot migration task writes to."
  value       = aws_cloudwatch_log_group.ecs["migrate"].name
}
