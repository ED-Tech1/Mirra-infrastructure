variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_suffix" {
  type        = string
  description = "Suffix to make the bucket name globally unique (AWS account id)."
}

variable "allowed_origins" {
  type        = list(string)
  description = "Origins allowed for presigned-upload CORS (the Vercel domains)."
  default     = []
}
