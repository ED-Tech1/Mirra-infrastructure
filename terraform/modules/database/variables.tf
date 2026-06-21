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
  description = "ID of the network the database should attach to"
}

variable "instance_class" {
  type        = string
  description = "Database instance size (provider-specific identifier)"
}

variable "allocated_storage_gb" {
  type        = number
  description = "Initial allocated storage in GB"
  default     = 20
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major.minor version"
  default     = "16.4"
}

variable "multi_az" {
  type        = bool
  description = "Enable multi-AZ deployment (prod) or single-AZ (dev)"
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain automated backups"
  default     = 7
}
