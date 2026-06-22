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
  address = var.vault_address
  # Authentication is handled via HCP Terraform JWT dynamic credentials.
  # VAULT_TOKEN is injected automatically at plan/apply time — no static token required.
}
