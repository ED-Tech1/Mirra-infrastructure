output "network_id" {
  description = "ID of the created virtual network"
  value       = null # to be set once provider resources are added
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = []
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = []
}

output "default_security_group_id" {
  description = "ID of the default security group"
  value       = null
}
