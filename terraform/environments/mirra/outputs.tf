output "cloudfront_url" {
  description = "Backend HTTPS base URL — set as the frontend's NEXT_PUBLIC_API_URL."
  value       = "https://${module.cdn.distribution_domain_name}"
}

output "cloudfront_distribution_id" {
  value = module.cdn.distribution_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ec2_instance_id" {
  value = module.compute.instance_id
}

output "rds_endpoint" {
  value     = module.database.endpoint
  sensitive = true
}

output "storage_bucket" {
  value = module.storage.bucket_id
}

output "backend_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN secret in mirra-backend."
  value       = aws_iam_role.backend_deploy.arn
}

output "infra_deploy_role_arn" {
  description = "Set as the TF_INFRA_ROLE_ARN secret in this repo."
  value       = aws_iam_role.infra_deploy.arn
}

output "vercel_env" {
  description = "Environment variables to set on the Vercel project."
  value = {
    NEXT_PUBLIC_API_URL  = "https://${module.cdn.distribution_domain_name}"
    NEXT_PUBLIC_APP_NAME = var.app_name
  }
}
