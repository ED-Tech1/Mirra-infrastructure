variable "project" {
  type    = string
  default = "mirra"
}

variable "environment" {
  type    = string
  default = "mirra"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_name" {
  type    = string
  default = "mirra"
}

variable "db_username" {
  type    = string
  default = "mirra"
}

variable "allowed_origins" {
  type        = list(string)
  description = "Vercel production and preview origins for backend CORS and S3 CORS."
}

variable "app_name" {
  type    = string
  default = "Mirra Trading"
}

variable "backend_repo" {
  type        = string
  description = "GitHub owner/repo of the backend repo, for OIDC sub scoping."
  default     = "ED-Tech1/Mira-repo"
}

variable "infra_repo" {
  type        = string
  description = "GitHub owner/repo of this infra repo, for OIDC sub scoping."
  default     = "ED-Tech1/Mirra-infrastructure"
}
