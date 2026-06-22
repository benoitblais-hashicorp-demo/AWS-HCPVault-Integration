variable "vault_address" {
  description = "(Required) The URL of your Vault instance."
  type        = string
}

variable "vault_server_ip" {
  description = "(Required) The public IP address of the Vault server allowed to access the RDS database."
  type        = string
}

variable "vault_token" {
  description = "(Required) Vault token with administrative privileges."
  type        = string
  sensitive   = true
}

variable "acme_email" {
  description = "(Optional) Email address for Let's Encrypt ACME account registration."
  type        = string
  default     = "benoit.blais@ibm.com"
}

variable "demo_namespace" {
  description = "(Optional) Vault namespace path for the demo. Must use lowercase letters, numbers, and underscores, and must start with demo_."
  type        = string
  default     = "demo_platform"

  validation {
    condition     = can(regex("^demo_[a-z0-9_]+$", var.demo_namespace))
    error_message = "The demo_namespace value must start with demo_ and contain only lowercase letters, numbers, and underscores."
  }
}

variable "admin_laptop_ip" {
  description = "(Optional) Public IP of your local laptop allowed to connect directly to the RDS instance for demo verification. Needs /32 suffix."
  type        = string
  default     = "" # Replace with your IP e.g. "123.45.67.89/32"
}

variable "aws_region" {
  description = "(Optional) The AWS region to deploy resources into."
  type        = string
  default     = "ca-central-1"
}

variable "force_cert_rotation" {
  description = "(Optional) A trigger to forcefully rotate the ALB Let's Encrypt certificate prematurely during demonstrations. Change this value to force rotation."
  type        = string
  default     = "1"
}

variable "private_hosted_zone" {
  description = "(Optional) Private Route53 Hosted Zone domain name for Vault internal PKI."
  type        = string
  default     = "benoit-blais.sbx.hashidemos.local"
}

variable "public_hosted_zone" {
  description = "(Optional) Public Route53 Hosted Zone domain name for Let's Encrypt certificates and external DNS."
  type        = string
  default     = "benoit-blais.sbx.hashidemos.io"
}

variable "vpc_cidr" {
  description = "(Optional) The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}
