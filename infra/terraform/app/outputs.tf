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
