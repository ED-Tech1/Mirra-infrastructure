variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "project" {
  type        = string
  description = "Project identifier used for naming and tagging"
}

variable "cidr_block" {
  type        = string
  description = "Primary CIDR block for the virtual network"
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  type        = number
  description = "Number of availability zones to span"
  default     = 2
}
