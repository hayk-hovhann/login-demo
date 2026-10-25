# The dashboard, in a production layout: a saved view of
# metrics the ALB, ECS and ElastiCache already publish for free. Created and
# destroyed with the stack, so it answers "is this session healthy right now",
# not long-term trends. Free: the first 3 dashboards are.
#
# Read top-down, the way an on-call engineer does: is anything alarming; are
# users served (the golden signals: traffic, errors, latency); is there
# capacity (targets, tasks); is anything saturating (CPU, memory); is the one
# dependency, Redis, healthy.
#
# CloudFormation wrote the body as a JSON string with ${} substitutions;
# jsonencode builds it from an HCL object instead, so a missing comma or quote
# is a plan error, not a body AWS rejects. Each metric is one list: namespace,
# metric name, dimension name/value pairs, then its options. Every name and
# dimension below was checked against list-metrics on a live stack: a wrong one
# draws an empty line, never an error.
locals {
  alb_suffix = aws_lb.main.arn_suffix

  # ServiceName as AWS/ECS publishes it.
  ecs_services = {
    backend  = aws_ecs_service.backend.name
    frontend = aws_ecs_service.frontend.name
  }

  # CacheClusterId is the node, login-demo-app-redis-001, not the replication
  # group. One line per node, so a replica added later shows up on its own.
  redis_nodes = sort(tolist(aws_elasticache_replication_group.redis.member_clusters))

  alarm_arns = concat(
    [aws_cloudwatch_metric_alarm.backend_5xx.arn],
    [for alarm in aws_cloudwatch_metric_alarm.unhealthy : alarm.arn],
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.app_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ---- Is anything alarming? ----
      {
        type   = "alarm"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          title  = "Alarms"
          alarms = local.alarm_arns
          # ALARM first, then INSUFFICIENT_DATA, then OK; newest change first.
          sortBy = "stateUpdatedTimestamp"
        }
      },

      # ---- Are users served? Traffic, errors, latency ----
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 8
        height = 6
        properties = {
          title   = "Requests per minute"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          metrics = [
            for key, tg in aws_lb_target_group.main :
            ["AWS/ApplicationELB", "RequestCount", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { stat = "Sum", label = key }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 3
        width  = 8
        height = 6
        properties = {
          # A rate, not a count: 10 errors in 20 requests is an outage, 10 in
          # 100,000 is noise. Metric math divides two hidden series; FILL turns
          # a minute with no 5xx (no datapoint) into 0 rather than a gap. The
          # IF guards the division: a minute with no requests, missing or a
          # published 0, is 0/0, which CloudWatch drops with a warning on every
          # legend entry. Guarded, it draws 0%; the requests graph beside this
          # one says whether there was any traffic.
          #
          # RequestCount leaves out requests rejected before a target was
          # chosen, and a 503 for a target group with no healthy target is
          # exactly that. So the ALB line adds its 503s back into the
          # denominator: without them, a total outage with no other traffic
          # would read 0%. 502 and 504 happen after a target is chosen and
          # are already counted. A target group's own line reads 0% in that
          # outage too, correctly: its app answered nothing.
          #
          # No 4xx: the frontend asks /api/auth/me on every page load, and an
          # anonymous visitor gets a 403, so 4xx is the normal path here.
          title   = "5xx error rate (%)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0 } }
          metrics = concat(
            [for key, tg in aws_lb_target_group.main : [{ expression = "IF(FILL(req_${key}, 0) > 0, 100 * FILL(err_${key}, 0) / FILL(req_${key}, 0), 0)", label = "${key} (app's own 5xx)", id = "rate_${key}" }]],
            [for key, tg in aws_lb_target_group.main : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { id = "err_${key}", stat = "Sum", visible = false }]],
            [for key, tg in aws_lb_target_group.main : ["AWS/ApplicationELB", "RequestCount", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { id = "req_${key}", stat = "Sum", visible = false }]],
            [
              [{ expression = "IF(FILL(req_alb, 0) + FILL(rej_alb, 0) > 0, 100 * FILL(err_alb, 0) / (FILL(req_alb, 0) + FILL(rej_alb, 0)), 0)", label = "ALB-generated 5xx", id = "rate_alb" }],
              ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_suffix, { id = "err_alb", stat = "Sum", visible = false }],
              ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_suffix, { id = "req_alb", stat = "Sum", visible = false }],
              ["AWS/ApplicationELB", "HTTPCode_ELB_503_Count", "LoadBalancer", local.alb_suffix, { id = "rej_alb", stat = "Sum", visible = false }],
            ],
          )
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 3
        width  = 8
        height = 6
        properties = {
          # Percentiles, not the average: p50 is the typical request, p99 the
          # slowest 1%, which an average hides.
          title   = "Backend latency (s)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          metrics = [
            for stat in ["p50", "p90", "p99"] :
            ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", aws_lb_target_group.main["backend"].arn_suffix, "LoadBalancer", local.alb_suffix, { stat = stat, label = stat }]
          ]
        }
      },

      # ---- Is there capacity? ----
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 8
        height = 6
        properties = {
          title   = "Healthy / unhealthy targets"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0 } }
          metrics = concat(
            [for key, tg in aws_lb_target_group.main : ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { stat = "Minimum", label = "${key} healthy" }]],
            [for key, tg in aws_lb_target_group.main : ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { stat = "Maximum", label = "${key} unhealthy" }]],
          )
          # The unhealthy alarms' threshold, drawn where they fire.
          annotations = { horizontal = [{ label = "alarm: < 1 healthy for 3 min", value = 1, fill = "below" }] }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 9
        width  = 8
        height = 6
        properties = {
          # Tasks ECS is running, draining ones included: a deploy shows as a
          # brief step up while old and new overlap. Free, unlike Container
          # Insights' RunningTaskCount.
          title   = "Running tasks"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0 } }
          metrics = [
            for key, name in local.ecs_services :
            ["AWS/ECS", "LiveTaskCount", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name, { stat = "Maximum", label = key }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 9
        width  = 8
        height = 6
        properties = {
          # Why the ALB answered for a target. 502: the target sent a bad
          # response or reset the connection. 503: no healthy target at all.
          # 504: the target was too slow. Connection errors: the ALB could not
          # reach a target, a security group or port mistake.
          title   = "ALB-generated errors (count)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          metrics = concat(
            [for code in ["502", "503", "504"] : ["AWS/ApplicationELB", "HTTPCode_ELB_${code}_Count", "LoadBalancer", local.alb_suffix, { stat = "Sum", label = code }]],
            [for key, tg in aws_lb_target_group.main : ["AWS/ApplicationELB", "TargetConnectionErrorCount", "TargetGroup", tg.arn_suffix, "LoadBalancer", local.alb_suffix, { stat = "Sum", label = "${key} connection errors" }]],
          )
        }
      },

      # ---- Is anything saturating? ----
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 12
        height = 6
        properties = {
          # Average across tasks and the busiest single task: one hot task
          # hides inside a calm average.
          title   = "ECS CPU (%)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = concat(
            [for key, name in local.ecs_services : ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name, { stat = "Average", label = "${key} avg" }]],
            [for key, name in local.ecs_services : ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name, { stat = "Maximum", label = "${key} busiest task" }]],
          )
          annotations = { horizontal = [{ label = "sustained above: resize or scale", value = 80 }] }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 15
        width  = 12
        height = 6
        properties = {
          # Memory is a hard limit on Fargate: at 100% the task is killed, not
          # slowed.
          title   = "ECS memory (%)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = concat(
            [for key, name in local.ecs_services : ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name, { stat = "Average", label = "${key} avg" }]],
            [for key, name in local.ecs_services : ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name, { stat = "Maximum", label = "${key} busiest task" }]],
          )
          annotations = { horizontal = [{ label = "sustained above: resize", value = 80 }] }
        }
      },

      # ---- Is the dependency healthy? Redis holds every session ----
      {
        type   = "metric"
        x      = 0
        y      = 21
        width  = 12
        height = 6
        properties = {
          # Engine CPU is Redis's own thread; Redis runs commands on one core,
          # so it saturates before the host does. Memory is the share of
          # maxmemory in use: at 100% Redis evicts, and an evicted session is a
          # user logged out.
          title   = "Redis CPU / memory (%)"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = concat(
            [for node in local.redis_nodes : ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", node, { stat = "Average", label = "${node} engine CPU" }]],
            [for node in local.redis_nodes : ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", node, { stat = "Average", label = "${node} host CPU" }]],
            [for node in local.redis_nodes : ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", node, { stat = "Maximum", label = "${node} memory" }]],
          )
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 21
        width  = 12
        height = 6
        properties = {
          # Connections: each backend task holds its own, on top of the few
          # ElastiCache keeps open to monitor the node (4-5 with no backend at
          # all). A fall back to that floor means the backend lost Redis.
          # Evictions, on the right axis, should stay 0.
          title   = "Redis connections / evictions"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.region
          period  = 60
          yAxis   = { left = { min = 0 }, right = { min = 0 } }
          metrics = concat(
            [for node in local.redis_nodes : ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", node, { stat = "Maximum", label = "${node} connections" }]],
            [for node in local.redis_nodes : ["AWS/ElastiCache", "Evictions", "CacheClusterId", node, { stat = "Sum", label = "${node} evictions", yAxis = "right" }]],
          )
        }
      },
    ]
  })
}
