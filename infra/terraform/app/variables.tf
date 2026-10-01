variable "network_stack_name" {
  description = "CloudFormation stack whose <name>-VpcId / -SubnetAId / -SubnetBId exports this config reads."
  type        = string
  default     = "login-demo-network"
}
