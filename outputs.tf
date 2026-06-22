output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.db_dynamic.endpoint
}

output "web_dynamic_public_ip" {
  description = "The public IP of the web server"
  value       = module.web_dynamic.public_ip
}

output "website_url" {
  description = "The final secured URL of your application"
  value       = "https://web-dynamic.${var.public_hosted_zone}"
}
