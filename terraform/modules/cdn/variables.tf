variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "origin_domain_name" {
  type        = string
  description = "EC2 public DNS used as the single custom origin."
}
