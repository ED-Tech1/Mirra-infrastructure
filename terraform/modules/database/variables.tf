variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type        = string
  description = "Security group of the app instance permitted to reach Postgres."
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "mirra"
}

variable "db_username" {
  type    = string
  default = "mirra"
}

variable "db_password" {
  type      = string
  sensitive = true
}
