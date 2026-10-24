variable "network_stack_name" {
  description = "CloudFormation stack whose <name>-VpcId / -SubnetAId / -SubnetBId exports this config reads."
  type        = string
  default     = "login-demo-network"
}

variable "data_stack_name" {
  description = "CloudFormation stack whose <name>-DbEndpoint / -DbPort / -DbName / -DbSecretArn / -DbClientSgId exports this config reads."
  type        = string
  default     = "login-demo-data"
}

variable "app_name" {
  description = "Prefix for the names of the resources this config creates."
  type        = string
  default     = "login-demo-app"
}

variable "backend_image_tag" {
  description = "Tag in the login-demo-backend ECR repo to run: latest, or a backend commit SHA. The migrate task runs migrate-<this tag>, so schema and code come from one commit."
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Tag in the login-demo-frontend ECR repo to run: latest, or a frontend commit SHA."
  type        = string
  default     = "latest"
}

variable "enable_exec" {
  description = "ECS Exec: a shell into a running backend task. Break-glass; leave false unless actively debugging."
  type        = bool
  default     = false
}

variable "registration_enabled" {
  description = "Allow POST /api/auth/register. True on purpose: each session starts from a fresh or restored DB with no seeding path on ECS, so the Register tab is the only way in. Set false to demonstrate the gate."
  type        = bool
  default     = true
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

