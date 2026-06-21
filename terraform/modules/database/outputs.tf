output "host" {
  description = "Database host"
  value       = null
}

output "port" {
  description = "Database port"
  value       = 5432
}

output "database_name" {
  description = "Default database name"
  value       = null
}

output "secret_id" {
  description = "Reference to the database credentials in the secret manager"
  value       = null
  sensitive   = true
}
