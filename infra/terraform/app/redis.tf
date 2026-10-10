# Redis, the session store. Its two security groups live in security_groups.tf.

# Which subnets ElastiCache may place the node in: RedisSubnetGroup in
# app-ecs.yaml. Free on its own; the node that uses it is what bills.
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.app_name}-redis"
  description = "Subnets ElastiCache may place the Redis node in."
  subnet_ids = [
    data.aws_cloudformation_export.subnet_a_id.value,
    data.aws_cloudformation_export.subnet_b_id.value,
  ]
}

# Single-node Redis, cluster mode disabled: RedisReplicationGroup in
# app-ecs.yaml. A replication group, not aws_elasticache_cluster, because the
# single-cluster endpoint rendered empty on engine 7.1 under CloudFormation.
# One primary, zero replicas. ~$0.016/hr, and the slowest thing here: measured
# 4m20s-5m31s to create, 6m32s-7m53s to destroy.
#
# No final_snapshot_identifier, so destroy deletes it outright: the
# DeletionPolicy: Delete of the CloudFormation version. Sessions are disposable.
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.app_name}-redis"
  description          = "${var.app_name} session store"

  engine             = "redis"
  engine_version     = "7.1"
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1
  port               = 6379

  # Failover needs a replica to promote; there is none.
  automatic_failover_enabled = false

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  # The backend dials redis://, not rediss://. The provider documents no
  # default for this, so it is pinned rather than left to AWS.
  transit_encryption_enabled = false
}
