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

variable "frontend_image_tag" {
  description = "Tag in the login-demo-frontend ECR repo to run: latest, or a frontend commit SHA."
  type        = string
  default     = "latest"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Null = HTTP only; set it and the ALB also admits 443."
  type        = string
  default     = null
}

variable "notification_email" {
  description = "Address the alarm topic emails. Null = no subscriber: the topic still exists, nobody hears from it."
  type        = string
  default     = null
}

