variable "bastion_name" {
  description = "Name of the instance and of its security group, role and instance profile."
  type        = string
  default     = "login-demo-bastion"
}

variable "network_parameter_path" {
  description = "SSM Parameter Store path the network config publishes its outputs under (its var.parameter_path)."
  type        = string
  default     = "/login-demo/network"
}

variable "data_parameter_path" {
  description = "SSM Parameter Store path the data config publishes its outputs under (its var.parameter_path)."
  type        = string
  default     = "/login-demo/data"
}

# Optional, so the bastion still applies with no app up: Redis lives in the
# ephemeral app, and a hard dependency would make DB-only sessions impossible.
# A separate badge on purpose, so GUI access to one datastore never implies
# access to the other.
variable "redis_client_security_group_id" {
  description = "The app's Redis client group, for 6379 reach: -var redis_client_security_group_id=$(terraform -chdir=infra/terraform/app output -raw redis_client_security_group_id). Null leaves the bastion Postgres-only."
  type        = string
  default     = null

  validation {
    condition     = var.redis_client_security_group_id == null ? true : can(regex("^sg-[0-9a-f]+$", var.redis_client_security_group_id))
    error_message = "redis_client_security_group_id must be a security group id (sg-...), or null."
  }
}
