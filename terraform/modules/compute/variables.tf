variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ecr_repository_url" {
  type = string
}

variable "storage_bucket_arn" {
  type = string
}

variable "secret_arns" {
  type        = map(string)
  description = "Map with keys: secret_key, database_url, allowed_origins."
}
