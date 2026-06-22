# ==============================================================================
# Vault Core Configuration
# ==============================================================================

# Dedicated namespace for all demo Vault resources
resource "vault_namespace" "demo_platform" {
  path = var.demo_namespace
}

# Enable AWS Authentication method for Vault Agent on the Web Server to authenticate and retrieve dynamic certificates
resource "vault_auth_backend" "aws" {
  namespace = vault_namespace.demo_platform.path_fq
  type      = "aws"
}

# KVv2 mount for demo secrets
resource "vault_mount" "kvv2" {
  namespace   = vault_namespace.demo_platform.path_fq
  path        = "kvv2"
  type        = "kv-v2"
  description = "KV v2 secrets for demo Linux credentials"
}

# Database Secrets Engine
resource "vault_mount" "db" {
  namespace   = vault_namespace.demo_platform.path_fq
  path        = "database"
  type        = "database"
  description = "Dynamic credentials for AWS RDS PostgreSQL"
}

# Configure the PostgreSQL Database Connection inside Vault
resource "vault_database_secret_backend_connection" "postgres" {
  namespace     = vault_namespace.demo_platform.path_fq
  backend       = vault_mount.db.path
  name          = "aws-rds-db-dynamic"
  allowed_roles = ["readonly", "webapp"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${aws_db_instance.db.endpoint}/${aws_db_instance.db.db_name}"
    username       = aws_db_instance.db.username
    password       = aws_db_instance.db.password
  }
}

# PRIVATE INTERNAL CERTIFICATE ORCHESTRATION (VAULT ROOT CA)
# ------------------------------------------------------------------------------

# Mount the Root PKI Secrets Engine
resource "vault_mount" "pki_root" {
  namespace                 = vault_namespace.demo_platform.path_fq
  path                      = "pki-root"
  type                      = "pki"
  description               = "Root CA for ${var.private_hosted_zone}"
  default_lease_ttl_seconds = 31536000  # 1 year
  max_lease_ttl_seconds     = 315360000 # 10 years
}

# Generate the Root Certificate
resource "vault_pki_secret_backend_root_cert" "pki_root_ca" {
  depends_on = [vault_mount.pki_root]
  namespace  = vault_namespace.demo_platform.path_fq
  backend    = vault_mount.pki_root.path

  type                 = "internal"
  common_name          = "${var.private_hosted_zone} Root CA"
  ttl                  = "315360000" # 10 years
  format               = "pem"
  private_key_format   = "der"
  key_type             = "rsa"
  key_bits             = 2048
  exclude_cn_from_sans = true
}

# Mount the Intermediate PKI Secrets Engine
resource "vault_mount" "pki_intermediate" {
  namespace                 = vault_namespace.demo_platform.path_fq
  path                      = "pki-intermediate"
  type                      = "pki"
  description               = "Intermediate CA for ${var.private_hosted_zone}"
  default_lease_ttl_seconds = 86400    # 1 day
  max_lease_ttl_seconds     = 31536000 # 1 year
}

# Generate an Intermediate CSR
resource "vault_pki_secret_backend_intermediate_cert_request" "pki_intermediate_csr" {
  namespace   = vault_namespace.demo_platform.path_fq
  backend     = vault_mount.pki_intermediate.path
  type        = "internal"
  common_name = "${var.private_hosted_zone} Intermediate CA"
  key_type    = "rsa"
  key_bits    = 2048
}

# Sign the Intermediate CSR with the Root CA
resource "vault_pki_secret_backend_root_sign_intermediate" "pki_intermediate_signed" {
  namespace   = vault_namespace.demo_platform.path_fq
  backend     = vault_mount.pki_root.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.pki_intermediate_csr.csr
  common_name = "${var.private_hosted_zone} Intermediate CA"
  ttl         = "157680000" # 5 years
  format      = "pem"
}

# Set the signed intermediate certificate
resource "vault_pki_secret_backend_intermediate_set_signed" "pki_intermediate_set" {
  namespace   = vault_namespace.demo_platform.path_fq
  backend     = vault_mount.pki_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.pki_intermediate_signed.certificate
  depends_on  = [vault_pki_secret_backend_root_sign_intermediate.pki_intermediate_signed]
}

# ==============================================================================
# NETWORKING ARCHITECTURE
# ==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Configuration
module "vpc" {
  source  = "app.terraform.io/benoitblais-hashicorp/vpc/aws"
  version = "0.0.1"

  name = "web-infra-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 2) : cidrsubnet(var.vpc_cidr, 8, k + 1)]
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 2) : cidrsubnet(var.vpc_cidr, 8, k + 10)]

  # Public subnets need to auto-assign public IPs for ALB and NAT GW
  map_public_ip_on_launch = true

  # Enable NAT Gateway for the private subnets to reach out (patching, Vault, etc.)
  enable_nat_gateway     = true
  single_nat_gateway     = true # Cost savings: 1 NAT GW for the demo instead of 1 per AZ
  one_nat_gateway_per_az = false

  enable_vpn_gateway = false
}

# ==============================================================================
# WEB SERVER ARCHITECTURE
# ==============================================================================

# SECURITY GROUPS
# ------------------------------------------------------------------------------

# Security Group for the Application Load Balancer
# Allows public access to the web app over standard HTTP/HTTPS ports.
module "alb_sg" {
  source  = "app.terraform.io/benoitblais-hashicorp/security-group/aws"
  version = "0.0.2"

  name        = "alb-dynamic-sg"
  description = "Security group for ALB allowing public HTTPS. HTTP is permitted only for 301 redirects."
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  # Maintain HTTP ingress purely to catch users typing 'benoit-blais.sbx...' and 301 redirect them to HTTPS.
  ingress_rules = ["http-80-tcp", "https-443-tcp"]

  egress_rules = ["all-all"]
}

# Security Group for the Web Server (Private)
# Prevents direct internet access to the EC2 instance, restricting traffic to the ALB.
module "web_sg" {
  source  = "app.terraform.io/benoitblais-hashicorp/security-group/aws"
  version = "0.0.2"

  name        = "web-dynamic-sg"
  description = "Security group for web server allowing traffic only from ALB"
  vpc_id      = module.vpc.vpc_id

  # Only allow traffic from the ALB
  ingress_with_source_security_group_id = [
    {
      # The ALB terminates public HTTPS and forwards to the target group over internal HTTPS port 443
      rule                     = "https-443-tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]

  # Allow SSH from Vault Server and Admin Laptop for demo operations
  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "Access from external Vault server"
      cidr_blocks = "${var.vault_server_ip}/32"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "Access from Admin Laptop for Demo Verification"
      cidr_blocks = var.admin_laptop_ip != "" ? var.admin_laptop_ip : "127.0.0.1/32"
    }
  ]

  egress_rules = ["all-all"]
}

# APPLICATION LOAD BALANCER
# ------------------------------------------------------------------------------

# Application Load Balancer
# Balances traffic to the private EC2 instances. Deletion protection disabled for easy demo teardown.
module "alb" {
  source  = "app.terraform.io/benoitblais-hashicorp/alb/aws"
  version = "0.0.1"

  name    = "alb-dynamic"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  # Allow Terraform to delete this ALB if we destroy the environment
  enable_deletion_protection = false

  # Ensure the security group is correctly passed
  security_groups = [module.alb_sg.security_group_id]

  # Redirect HTTP to HTTPS and terminate public TLS at ALB with ACM certificate
  listeners = {
    http-80 = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https-443 = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate_validation.public.certificate_arn
      forward = {
        target_group_key = "web-dynamic-tg"
      }
    }
  }

  target_groups = {
    web-dynamic-tg = {
      name_prefix       = "webdyn"
      protocol          = "HTTPS"
      port              = 443
      target_type       = "instance"
      create_attachment = false # We attach it below
    }
  }
}

# Attach EC2 Instance to the ALB Target Group
resource "aws_lb_target_group_attachment" "web_attachment" {
  target_group_arn = module.alb.target_groups["web-dynamic-tg"].arn
  target_id        = module.web.id
  port             = 443
}

# PUBLIC CERTIFICATE ORCHESTRATION (AWS ACM + ROUTE53)
# ------------------------------------------------------------------------------

# Fetch the existing Route 53 zone for public DNS records
data "aws_route53_zone" "demo" {
  name = var.public_hosted_zone
}

# Request a public certificate in ACM for the ALB listener
resource "aws_acm_certificate" "public" {
  domain_name       = "web-dynamic.${var.public_hosted_zone}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Publish ACM DNS validation records in Route53
resource "aws_route53_record" "public_validation" {
  for_each = {
    for dvo in aws_acm_certificate.public.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.demo.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]

  allow_overwrite = true
}

# Complete ACM certificate validation after DNS records are visible
resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [for record in aws_route53_record.public_validation : record.fqdn]
}

# Map the public website DNS fully to the AWS Load Balancer
resource "aws_route53_record" "web_dns_record" {
  zone_id = data.aws_route53_zone.demo.zone_id
  name    = "web-dynamic.${var.public_hosted_zone}"
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}

# Create a role for issuing internal certificates
resource "vault_pki_secret_backend_role" "internal_web" {
  namespace = vault_namespace.demo_platform.path_fq
  backend   = vault_mount.pki_intermediate.path

  name          = "internal-web-role"
  ttl           = 86400 # Certificates valid for 24h
  allow_ip_sans = true
  key_type      = "rsa"
  key_bits      = 2048

  # Limit this role to only issue certificates for the local zone
  allowed_domains    = [var.private_hosted_zone]
  allow_subdomains   = true
  allow_glob_domains = false
  allow_any_name     = false
  enforce_hostnames  = true
  generate_lease     = true
}

# AWS Authentication for Vault Agent
# ------------------------------------------------------------------------------
resource "vault_policy" "agent_pki" {
  namespace = vault_namespace.demo_platform.path_fq
  name      = "agent-pki-policy"
  policy    = <<POLICY
path "pki-intermediate/issue/internal-web-role" {
  capabilities = ["update"]
}
POLICY
}

resource "vault_aws_auth_backend_client" "aws" {
  namespace = vault_namespace.demo_platform.path_fq
  backend   = vault_auth_backend.aws.path
}

resource "vault_aws_auth_backend_role" "web_agent" {
  namespace                = vault_namespace.demo_platform.path_fq
  backend                  = vault_auth_backend.aws.path
  role                     = "web-agent-role"
  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.ssm_role.arn]
  resolve_aws_unique_ids   = false
  token_policies           = ["default", vault_policy.agent_pki.name]
}

# Map this directly to the Private IP of our Web Server EC2 instance
# Fetch the existing Route 53 zone for internal DNS records
data "aws_route53_zone" "internal" {
  name         = var.private_hosted_zone
  private_zone = true
}

resource "aws_route53_record" "web_internal_record" {
  zone_id = data.aws_route53_zone.internal.zone_id
  name    = "web-dynamic.${var.private_hosted_zone}"
  type    = "A"
  ttl     = 300
  records = [module.web.private_ip]
}

# EC2 INSTANCE (WEB SERVER)
# ------------------------------------------------------------------------------

# IAM Role for SSM Session Manager
# Security Best Practice: No inbound SSH directly over Internet, access securely via Systems Manager
resource "aws_iam_role" "ssm_role" {
  name = "web_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "web_ssm_profile"
  role = aws_iam_role.ssm_role.name
}

# Generate passwords for Linux users and store them in Vault KV v2
resource "random_password" "os_linuxadmin_password" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "random_password" "os_appuser_password" {
  length           = 32
  special          = true
  override_special = "-_"
}

# Store Linux credentials in KV v2
resource "vault_kv_secret_v2" "linux_vm_credentials" {
  namespace = vault_namespace.demo_platform.path_fq
  mount     = vault_mount.kvv2.path
  name      = "linux/web-dynamic"
  data_json = jsonencode({
    linuxadmin_password = random_password.os_linuxadmin_password.result
    appuser_password    = random_password.os_appuser_password.result
  })
}

# Policy for authorized readers of Linux credentials in KV
resource "vault_policy" "linux_credentials_readers" {
  namespace = vault_namespace.demo_platform.path_fq
  name      = "linux-credentials-readers"
  policy    = <<POLICY
path "kvv2/data/linux/web-dynamic" {
  capabilities = ["read"]
}

path "kvv2/metadata/linux/*" {
  capabilities = ["list", "read"]
}
POLICY
}

# EC2 Instance utilizing official AWS module
# Fetch the most recent private RHEL 9 AMI
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["888995627335"] # ami-prod account

  filter {
    name   = "name"
    values = ["hc-base-rhel-9-x86_64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "web" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.6"

  name = "web-dynamic"

  ami           = data.aws_ami.rhel9.id
  instance_type = "t3.small"

  # Inject startup script to seed the DB and install the web app
  user_data = templatefile("${path.module}/scripts/bootstrap_web-dynamic.sh", {
    db_host            = aws_db_instance.db.address
    db_port            = aws_db_instance.db.port
    db_name            = aws_db_instance.db.db_name
    db_user            = aws_db_instance.db.username
    db_password        = aws_db_instance.db.password
    linuxadmin_initial = random_password.os_linuxadmin_password.result
    appuser_initial    = random_password.os_appuser_password.result
    # Passing Vault config to the EC2 so Vault Agent can authenticate via AWS IAM and auto-rotate internal certs
    vault_address = var.vault_address
    pki_namespace = vault_namespace.demo_platform.path_fq
    aws_auth_path = vault_auth_backend.aws.path
    private_zone  = var.private_hosted_zone
  })
  user_data_replace_on_change = true

  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.web_sg.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name

  # Security best practice: IMDSv2 enabled
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

# ==============================================================================
# DATABASE ARCHITECTURE
# ==============================================================================

# DATABASE SECURITY GROUP
# ------------------------------------------------------------------------------

# Database Security Group
# Required to accept connections from Vault to rotate dynamic secrets,
# as well as the Web Server hosting the frontend application.
module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "db-dynamic-sg"
  description = "Security group for RDS allowing Vault and Web Server"
  vpc_id      = module.vpc.vpc_id

  # Allow access from the Vault Server IP only
  ingress_with_cidr_blocks = [
    {
      rule        = "postgresql-tcp"
      cidr_blocks = "${var.vault_server_ip}/32"
      description = "Access from external Vault server"
    },
    {
      rule        = "postgresql-tcp"
      cidr_blocks = var.admin_laptop_ip != "" ? var.admin_laptop_ip : "127.0.0.1/32"
      description = "Access from Admin Laptop for Demo Verification"
    }
  ]

  # Allow access from the Web Server
  ingress_with_source_security_group_id = [
    {
      rule                     = "postgresql-tcp"
      source_security_group_id = module.web_sg.security_group_id
      description              = "Access from internal Web Server"
    }
  ]

  egress_rules = ["all-all"]
}

# DATABASE INSTANCE
# ------------------------------------------------------------------------------

# DB Subnet Group mapped to Public Subnets for Vault accessibility
resource "aws_db_subnet_group" "db_subnet_group" {
  name = "public-db-subnets"
  # Placed in the public subnets so external Vault can reach it for JIT secret generation
  subnet_ids = module.vpc.public_subnets
}

# Database credentials injected temporarily to application script during startup
# In a full Vault adoption, Vault agent would fetch this directly without being rendered here.
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AWS RDS PostgreSQL Instance
# Configured as publicly accessible purely for the demo so external Vault can 
# route internal dynamic DB secrets without a VPN/VPC connection.
# Deletion protection is skipped so tear-downs are seamless.
resource "aws_db_instance" "db" {
  identifier        = "vault-demo-postgres"
  engine            = "postgres"
  engine_version    = "15" # AWS will use the most robust available 15.x patch
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = "appdb"
  username          = "dbadmin"
  password          = random_password.db_password.result

  # Required to be Public so external Vault can connect and manage roles
  publicly_accessible    = true
  vpc_security_group_ids = [module.db_sg.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  skip_final_snapshot    = true
}

# Create a Database Role mapped to dynamically generated credentials
# Limits lateral movement by generating one-off temporary passwords 
resource "vault_database_secret_backend_role" "webapp" {
  namespace = vault_namespace.demo_platform.path_fq
  backend   = vault_mount.db.path
  name      = "webapp"
  db_name   = vault_database_secret_backend_connection.postgres.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, UPDATE, INSERT, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";"
  ]
  default_ttl = 300  # 5 minutes for rapid demo expiration
  max_ttl     = 3600 # 1 hour max
}

# Generate an ACL Policy mapped for consuming the dynamic DB role
resource "vault_policy" "webapp_db_policy" {
  namespace = vault_namespace.demo_platform.path_fq
  name      = "webapp-database-policy"
  policy    = <<POLICY
# Allow generating dynamic database credentials
path "database/creds/webapp" {
  capabilities = ["read"]
}
POLICY
}
