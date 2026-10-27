variable "network_parameter_path" {
  description = "SSM Parameter Store path the network config publishes its outputs under (its var.parameter_path)."
  type        = string
  default     = "/login-demo/network"
}

variable "data_name" {
  description = "Prefix for the names of the resources this config creates."
  type        = string
  default     = "login-demo-data"
}

variable "instance_class" {
  description = "RDS instance class. db.t3.micro is the cheap learning default."
  type        = string
  default     = "db.t3.micro"
}

variable "snapshot_identifier" {
  description = "Null for a fresh, blank database. A snapshot id or ARN restores from it instead: how data survives a teardown."
  type        = string
  default     = null
}

variable "parameter_path" {
  description = "SSM Parameter Store path this config publishes its outputs under, one parameter per output."
  type        = string
  default     = "/login-demo/data"
}
