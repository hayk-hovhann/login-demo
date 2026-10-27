# Scheme from the listener shape, host from the ALB. Under the domain
# certificate the browser address is the per-session app CNAME instead: the
# ALB's own name isn't on that cert, so a browser would warn.
output "url" {
  description = "App URL: frontend at /, backend at /api/*."
  value       = "${local.tls ? "https" : "http"}://${aws_lb.main.dns_name}"
}

# What run-migration.sh passes to run-task.
output "migrate_task_definition_family" {
  description = "Family of the one-shot Prisma migration task. Run it with ./infra/run-migration.sh."
  value       = aws_ecs_task_definition.migrate.family
}

# run-migration.sh and make-cert.sh read the cluster's name here rather than
# rebuilding it from the app name.
output "cluster_name" {
  description = "ECS cluster the services and the migration task run in."
  value       = aws_ecs_cluster.main.name
}

# The bastion takes this ID as its redis_client_security_group_id variable,
# passed with -var, when a session needs redis-tunnel.sh.
output "redis_client_security_group_id" {
  description = "Attach to anything that needs Redis on 6379 (the bastion, for GUI tunneling)."
  value       = aws_security_group.redis_client.id
}

# The backend's REDIS_URL is redis://<this>.
output "redis_endpoint" {
  description = "host:port of the Redis primary."
  value       = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

# The backend task definition hands ECS this ARN to inject as SESSION_SECRET,
# and the execution role must be allowed to read it.
output "session_secret_arn" {
  description = "Secrets Manager ARN holding the express-session signing key."
  value       = aws_secretsmanager_secret.session.arn
}

# The bare hostname, no scheme. The per-session app CNAME points at it, and
# make-cert.sh:120 reads it as the name its certificate must cover.
output "alb_dns_name" {
  description = "ALB DNS name, with no scheme. The app CNAME's target."
  value       = aws_lb.main.dns_name
}

# One click from the terminal to the dashboard.
output "dashboard_url" {
  description = "CloudWatch console link to this session's dashboard."
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# run-migration.sh attaches it beside the DB badge, which has no egress.
output "migrate_security_group_id" {
  description = "Main security group of the one-shot migration task: outbound only."
  value       = aws_security_group.migrate.id
}

# run-migration.sh reads it to tail the migration's logs.
output "migrate_log_group_name" {
  description = "CloudWatch log group the one-shot migration task writes to."
  value       = aws_cloudwatch_log_group.ecs["migrate"].name
}
