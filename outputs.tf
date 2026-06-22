output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.db.endpoint
}

output "web_public_ip" {
  description = "The public IP of the web server"
  value       = module.web.public_ip
}

output "website_url" {
  description = "The final secured URL of your application"
  value       = "https://web-dynamic.${var.public_hosted_zone}"
}
