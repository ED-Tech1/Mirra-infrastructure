variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "project" {
  type        = string
  description = "Project identifier"
}

variable "network_id" {
  type        = string
  description = "ID of the network the API should run in"
}

variable "image_reference" {
  type        = string
  description = "Container image reference (registry/repo:tag) for the API"
}

variable "database_secret_id" {
  type        = string
  description = "Reference to the database credentials in the secret manager"
  sensitive   = true
}

variable "app_secret_id" {
  type        = string
  description = "Reference to the application secret (JWT signing key, etc.)"
  sensitive   = true
}

variable "min_instances" {
  type        = number
  description = "Minimum number of API instances"
  default     = 1
}

variable "max_instances" {
  type        = number
  description = "Maximum number of API instances"
  default     = 3
}

variable "allowed_origins" {
  type        = list(string)
  description = "CORS allowed origins (the frontend hostnames)"
  default     = []
}
