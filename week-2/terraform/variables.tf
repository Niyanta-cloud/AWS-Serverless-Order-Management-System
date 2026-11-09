# INPUT SETTINGS
# These variables let the project name, region, and log retention be configured.
variable "aws_region" {
  description = "AWS region for the demo stack."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short prefix used for resource names; use a lowercase alphanumeric/hyphen value."
  type        = string
  default     = "orderflow-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "project_name must be 3-25 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "log_retention_days" {
  description = "CloudWatch retention for Lambda logs."
  type        = number
  default     = 14
}
