variable "network_name" {
  description = "Prefix for the Name tags of the resources this config manages. The CloudFormation stack's name, so the adopted resources keep theirs."
  type        = string
  default     = "login-demo-network"
}

variable "parameter_path" {
  description = "SSM Parameter Store path this config publishes its outputs under, one parameter per output."
  type        = string
  default     = "/login-demo/network"
}
