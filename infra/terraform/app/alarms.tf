# SNS topic: the fan-out point between the alarms and whoever must hear about
# them. An alarm publishes to the topic and never knows the subscribers, so
# adding one (Slack, a pager) never touches an alarm. The topic is free; email
# deliveries are free up to 1,000 a month.
resource "aws_sns_topic" "alarms" {
  name = "${var.app_name}-alarms"
}

# No address, no subscriber. count = 0 creates nothing; one address makes
# aws_sns_topic_subscription.alarm_email[0].
#
# SNS first mails a confirmation link and delivers nothing until it is clicked.
# A new topic every session means a new link every session. Terraform cannot
# delete a subscription still pending confirmation, only drop it from state;
# destroy stays clean anyway, because deleting a topic deletes every
# subscription on it.
resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.notification_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# The backend is up but erroring: its tasks answered more than 5 HTTP 5xx in
# one minute. Target 5xx means the app itself threw (a bug); the ALB's own 5xx,
# no target reachable, is a different metric. Sparse: emitted only when a 5xx
# happens, so missing data counts as healthy. Free: the first 10 alarms are.
resource "aws_cloudwatch_metric_alarm" "backend_5xx" {
  alarm_name        = "${var.app_name}-backend-5xx"
  alarm_description = "Backend returned more than 5 HTTP 5xx responses in a minute."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  dimensions = {
    TargetGroup  = aws_lb_target_group.main["backend"].arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # Mail on the way into ALARM, and again on the way back to OK: the all-clear.
  # Any move to OK counts, including the first one out of INSUFFICIENT_DATA, so
  # every apply that creates the alarms mails one OK per alarm.
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Fires when a target group has had no healthy task for 3 straight minutes.
# One per target group, keyed like them:
# aws_cloudwatch_metric_alarm.unhealthy["frontend"]. The frontend's matters as
# much as the backend's: without it, a frontend crash-loop churns tasks for
# minutes with nothing alerting.
resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  for_each = aws_lb_target_group.main

  alarm_name        = "${var.app_name}-${each.key}-unhealthy"
  alarm_description = "The ${each.key} target group had no healthy tasks for 3 minutes."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"
  dimensions = {
    TargetGroup  = each.value.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  # Minimum: a minute counts as down if the count touched 0 at all.
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
