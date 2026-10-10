# vpc_id and subnet_ids are temporary: they prove the network exports resolve.
# Replaced by the real outputs (URL, LoadBalancerDnsName, ...) as resources land.

output "vpc_id" {
  value = data.aws_cloudformation_export.vpc_id.value
}

output "subnet_ids" {
  value = [
    data.aws_cloudformation_export.subnet_a_id.value,
    data.aws_cloudformation_export.subnet_b_id.value,
  ]
}

# RedisClientSgId in app-ecs.yaml, minus the Export: Terraform cannot create
# CloudFormation exports, so bastion.yaml:101's ImportValue finds nothing.
# The bastion has to take this ID as a parameter instead.
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

# MigrateLogGroupName in app-ecs.yaml. run-migration.sh:44 reads it to tail the
# migration's logs; at cutover it switches to terraform output -raw.
output "migrate_log_group_name" {
  description = "CloudWatch log group the one-shot migration task writes to."
  value       = aws_cloudwatch_log_group.ecs["migrate"].name
}
