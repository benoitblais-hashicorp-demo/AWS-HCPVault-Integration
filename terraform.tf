terraform {
  cloud {
    organization = "benoitblais-hashicorp"

    workspaces {
      name = "aws-vault-integration"
    }
  }
}
