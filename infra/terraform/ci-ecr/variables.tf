variable "github_org" {
  description = "GitHub account that owns the repository CD runs in."
  type        = string
  default     = "hayk-hovhann"
}

variable "github_repo" {
  description = "Repository whose main-branch workflows may assume the role."
  type        = string
  default     = "login-demo"
}
