variable "environment" {
  description = "Environment name (dev, prod). Used for outputs and sanity checks only."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "cluster_id" {
  description = "Redpanda Cloud BYOC cluster ID for this environment."
  type        = string
}

variable "topic_partitions" {
  description = "Partition count for the demo topic."
  type        = number
  default     = 3
}

variable "app_user_password" {
  description = "SCRAM password for the application user. Supplied via TF_VAR_app_user_password; never written to state or plan."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "app_user_password_version" {
  description = "Bump to rotate the app user's password (write-only attributes cannot be diffed)."
  type        = number
  default     = 1
}

variable "allow_deletion" {
  description = "Whether Terraform may delete the Redpanda resources. Keep false in prod."
  type        = bool
  default     = false
}
