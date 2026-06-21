output "instance_id" {
  value = aws_instance.this.id
}

output "instance_public_dns" {
  description = "Stable public DNS of the Elastic IP; used as the CloudFront origin."
  value       = "ec2-${replace(aws_eip.this.public_ip, ".", "-")}.${var.region}.compute.amazonaws.com"
}

output "security_group_id" {
  value = aws_security_group.ec2.id
}
