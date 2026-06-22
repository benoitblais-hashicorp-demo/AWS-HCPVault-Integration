provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "Demo"
      Project     = "AWS-Vault-Integration"
      ManagedBy   = "Terraform"
    }
  }
}

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = true # Required for self-signed or invalid certs on the demo Vault server
}
