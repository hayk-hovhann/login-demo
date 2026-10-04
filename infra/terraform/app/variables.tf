variable "network_stack_name" {
  description = "CloudFormation stack whose <name>-VpcId / -SubnetAId / -SubnetBId exports this config reads."
  type        = string
  default     = "login-demo-network"
}

variable "app_name" {
  description = "Prefix for the names of the resources this config creates."
  type        = string
  default     = "login-demo-app"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Null = HTTP only; set it and the ALB also admits 443."
  type        = string
  default     = null
}

