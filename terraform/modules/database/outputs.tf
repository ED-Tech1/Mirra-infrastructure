output "endpoint" {
  description = "Connection endpoint in host:port form."
  value       = aws_db_instance.this.endpoint
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}
