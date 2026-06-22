<!-- BEGIN_TF_DOCS -->
# HashiCorp Vault Integrations on AWS

This repository provides an end-to-end Terraform architecture demonstrating HashiCorp Vault integrations on AWS. It orchestrates core AWS infrastructure (VPC, EC2, RDS, ALB) together with a dynamic Vault design focused on KV v2 Linux credentials, dynamic database credentials, and internal PKI.

## What this demo demonstrates

This demo showcases the power of HashiCorp Vault in centralizing and automating secret management across infrastructure and applications. It highlights the transition from long-lived credentials to ephemeral, Vault-managed secrets that are securely stored, issued, and consumed by workloads.

## Features

* **Machine Identity (AWS IAM Auth)**: Secure authentication to Vault using native AWS EC2 IAM instance profiles.
* **Vault KV v2**: Storage for Linux VM password material used during bootstrap and operational access.
* **Vault Database Secrets Engine**: Ephemeral PostgreSQL database credentials for zero-trust database access.
* **Vault PKI (Internal)**: Root and intermediate PKI for private certificate issuance inside the demo namespace.
* **AWS ACM**: Public-facing ALB certificates managed by AWS Certificate Manager.
* **HashiCorp Terraform**: Standardized infrastructure-as-code modules for AWS deployments (VPC, EC2, ALB, RDS, Security Groups).

## Demo Components

* **Network Architecture**: Foundational AWS VPC, Public/Private Subnets, and NAT Gateway.
* **Web Application**: An EC2 instance securely bootstrapped using Vault-managed credentials and internal certificate material.
* **Database**: An AWS RDS PostgreSQL instance serving as the application backend.
* **Load Balancing & DNS**: Application Load Balancers securing incoming internet traffic, mapped via Route53.

## How this demo works

Terraform provisions the AWS networking and compute infrastructure. It also bootstraps the Vault environment, mounting the namespace, KV v2, PKI, AWS auth, and Database Secret engines. The EC2 web server starts up and connects to the PostgreSQL RDS database using dynamically managed credentials, serving a web UI with ACM-backed public TLS and Vault-managed internal trust.

## Demo Value Proposition

1. **Zero Trust Security**: Eliminates static, long-lived SSH keys and database passwords.
2. **Automated Certificate Lifecycle**: Drastically reduces the operational overhead of internal PKI renewal and provisioning.
3. **Machine Identity Integration**: Removes the "Secret Zero" problem by using innate cloud identities (AWS IAM) for seamless Vault authentication from the EC2 instance.
4. **Standardization**: Illustrates the shift to modular, scalable Terraform code managing Vault integrations cleanly.

## How to Conduct the Demo

*Prerequisite*: Add your laptop IP to the Terraform `admin_laptop_ip` variable if you want local SSH or database access during the demo.

1. **Showcase the Dynamic Web App:**
   Navigate to the `website_url` output (e.g. `https://web-dynamic.benoit-blais.sbx.hashidemos.io`) to show the secured application running correctly with an ACM-backed public certificate.
2. **Demonstrate OS Access:**
   * Retrieve the Linux password material from Vault KV v2.
   * Use the generated credential to SSH into the EC2 instance as needed for demo operations.
3. **Demonstrate Automated Certificate Rotation:**
   * **Public Certificate (AWS ACM)**: Show that the application is directly running via the Application Load Balancer using an ACM-backed certificate.
   * **Internal Certificates (Vault PKI)**: In the Vault UI, show the `pki-root` and `pki-intermediate` secret engine mounts.
   * While connected to the EC2 instance via SSH, run the following command to view the physical bundle managed by the workload:

     ```bash
     openssl x509 -in /opt/app/bundle.pem -text -noout | grep -A 2 "Validity"
     ```

   * To prove the web server is actively serving traffic using this certificate, run the following command directly on the EC2 instance to poll the local listener:

     ```bash
     curl -v --cacert /opt/app/bundle.pem https://localhost/ 2>&1 | grep "expire date"
     ```

   * If you rotate the internal certificate, rerun the commands to show the updated validity window.
4. **Demonstrate Automated OS Password Rotation:**
   * Reissue the Linux password material from Vault KV v2 to show the value changes when rotated.
   * Attempt to SSH using the previous credential. The connection should fail once the password has been updated.
   * Demonstrate that SSH access is immediately permitted when using the newly minted password.
5. **Demonstrate Dynamic Database Credentials:**
   * Request a temporary database credential: `vault read database/creds/webapp`
    * Open pgAdmin4 and create a new connection using the RDS Endpoint output from Terraform as the host.
    * Use these connection values:

       ```text
       Host name/address: <rds_endpoint output>
       Port: 5432
       Maintenance database: appdb
       Username: <username from vault read database/creds/webapp>
       Password: <password from vault read database/creds/webapp>
       ```

    * After connecting, open the `appdb` database and update the `demo_content` table to showcase real-time read/write access.
   * Update a record in the `demo_content` table to showcase real-time read/write access:

     ```sql
     UPDATE demo_content SET message = 'Live Vault Demo Successful!' WHERE id = 1;
     ```

   * Reload the web page to show the live database update.
6. **Wait for Expiration:**
   * Wait a few minutes for the TTL to expire (the default demo database lease is an ultra-short **300s / 5 minutes**), or actively revoke the lease in Vault to forcefully bypass the timer.
   * Attempt to connect to the database again using the identical dynamic credentials. Access will be explicitly denied, proving zero-trust enforcement.

## Expected Behavior

* The web server will output a success message pulling live data from the database.
* You will be able to retrieve temporary passwords from Vault.
* Direct database and OS access using expired Vault passwords will be explicitly denied.

## Permissions

### AWS Provider Permissions

**Required IAM Permissions**: The role or user must have sufficient rights to manage VPCs, Subnets, EC2 Instances, Route53 Zones/Records, Application Load Balancers, Target Groups, ACM Certificates, IAM Roles/Profiles, and RDS instances.

### Vault Provider Permissions

**Required Vault Permissions**: The token must be attached to a policy granting administrative rights to mount secret engines (`sys/mounts/*`), configure `pki`, `kv-v2`, `aws`, and `database` engines, and create corresponding roles and policies.

## Authentications

### AWS Provider Authentication

To provision resources on AWS, Terraform requires authentication. You can authenticate using any of the standard methods supported by the AWS Provider.

* **OIDC via HCP Terraform (Recommended)**: For VCS-driven workflows, configure HCP Terraform to use Dynamic Provider Credentials to assume an AWS IAM role.
* **Environment Variables**: Export standard AWS credentials for local debugging.

  ```bash
  export AWS_ACCESS_KEY_ID="anaccesskey"
  export AWS_SECRET_ACCESS_KEY="asecretkey"
  export AWS_SESSION_TOKEN="asessiontoken" # optional
  export AWS_REGION="ca-central-1"
  ```

* **Shared Credentials File**: Use an AWS profile defined in `~/.aws/credentials`.

### Vault Provider Authentication

The `vault` provider authenticates using HCP Terraform dynamic credentials via JWT. No static Vault token is used or required.

* **HCP Terraform / JWT Auth**: The HCP Terraform workspace is configured to authenticate to Vault using a trusted JWT identity. The Vault provider receives a short-lived token automatically at plan and apply time.
* **Required workspace variables**: `VAULT_ADDR` must be set in the HCP Terraform workspace pointing to your HCP Vault cluster endpoint.

## Documentation

## Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) (>= 1.5.0)

- <a name="requirement_aws"></a> [aws](#requirement\_aws) (~> 5.0)

- <a name="requirement_random"></a> [random](#requirement\_random) (~> 3.5.0)

- <a name="requirement_vault"></a> [vault](#requirement\_vault) (>= 4.0.0)

## Modules

The following Modules are called:

### <a name="module_alb"></a> [alb](#module\_alb)

Source: app.terraform.io/benoitblais-hashicorp/alb/aws

Version: 0.0.1

### <a name="module_alb_sg"></a> [alb\_sg](#module\_alb\_sg)

Source: app.terraform.io/benoitblais-hashicorp/security-group/aws

Version: 0.0.2

### <a name="module_db_sg"></a> [db\_sg](#module\_db\_sg)

Source: terraform-aws-modules/security-group/aws

Version: ~> 5.0

### <a name="module_vpc"></a> [vpc](#module\_vpc)

Source: app.terraform.io/benoitblais-hashicorp/vpc/aws

Version: 0.0.1

### <a name="module_web"></a> [web](#module\_web)

Source: terraform-aws-modules/ec2-instance/aws

Version: ~> 5.6

### <a name="module_web_sg"></a> [web\_sg](#module\_web\_sg)

Source: app.terraform.io/benoitblais-hashicorp/security-group/aws

Version: 0.0.2

## Required Inputs

The following input variables are required:

### <a name="input_vault_address"></a> [vault\_address](#input\_vault\_address)

Description: (Required) The URL of your Vault instance.

Type: `string`

### <a name="input_vault_server_ip"></a> [vault\_server\_ip](#input\_vault\_server\_ip)

Description: (Required) The public IP address of the Vault server allowed to access the RDS database.

Type: `string`

## Optional Inputs

The following input variables are optional (have default values):

### <a name="input_admin_laptop_ip"></a> [admin\_laptop\_ip](#input\_admin\_laptop\_ip)

Description: (Optional) Public IP of your local laptop allowed to connect directly to the RDS instance for demo verification. Needs /32 suffix.

Type: `string`

Default: `""`

### <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region)

Description: (Optional) The AWS region to deploy resources into.

Type: `string`

Default: `"ca-central-1"`

### <a name="input_demo_namespace"></a> [demo\_namespace](#input\_demo\_namespace)

Description: (Optional) Vault namespace path for the demo. Must use lowercase letters, numbers, and underscores, and must start with demo\_.

Type: `string`

Default: `"demo_platform"`

### <a name="input_private_hosted_zone"></a> [private\_hosted\_zone](#input\_private\_hosted\_zone)

Description: (Optional) Private Route53 Hosted Zone domain name for Vault internal PKI.

Type: `string`

Default: `"benoit-blais.sbx.hashidemos.local"`

### <a name="input_public_hosted_zone"></a> [public\_hosted\_zone](#input\_public\_hosted\_zone)

Description: (Optional) Public Route53 Hosted Zone domain name for Let's Encrypt certificates and external DNS.

Type: `string`

Default: `"benoit-blais.sbx.hashidemos.io"`

### <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr)

Description: (Optional) The CIDR block for the VPC.

Type: `string`

Default: `"10.0.0.0/16"`

## Resources

The following resources are used by this module:

- [aws_acm_certificate.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) (resource)
- [aws_acm_certificate_validation.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) (resource)
- [aws_db_instance.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) (resource)
- [aws_db_subnet_group.db_subnet_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) (resource)
- [aws_iam_instance_profile.ssm_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) (resource)
- [aws_iam_role.ssm_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) (resource)
- [aws_iam_role_policy_attachment.ssm_core_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) (resource)
- [aws_lb_target_group_attachment.web_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) (resource)
- [aws_route53_record.public_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) (resource)
- [aws_route53_record.web_dns_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) (resource)
- [aws_route53_record.web_internal_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) (resource)
- [random_password.db_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) (resource)
- [random_password.os_appuser_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) (resource)
- [random_password.os_linuxadmin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) (resource)
- [vault_auth_backend.aws](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/auth_backend) (resource)
- [vault_aws_auth_backend_client.aws](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/aws_auth_backend_client) (resource)
- [vault_aws_auth_backend_role.web_agent](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/aws_auth_backend_role) (resource)
- [vault_database_secret_backend_connection.postgres](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/database_secret_backend_connection) (resource)
- [vault_database_secret_backend_role.webapp](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/database_secret_backend_role) (resource)
- [vault_kv_secret_v2.linux_vm_credentials](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/kv_secret_v2) (resource)
- [vault_mount.db](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/mount) (resource)
- [vault_mount.kvv2](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/mount) (resource)
- [vault_mount.pki_intermediate](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/mount) (resource)
- [vault_mount.pki_root](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/mount) (resource)
- [vault_namespace.demo_platform](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/namespace) (resource)
- [vault_pki_secret_backend_intermediate_cert_request.pki_intermediate_csr](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/pki_secret_backend_intermediate_cert_request) (resource)
- [vault_pki_secret_backend_intermediate_set_signed.pki_intermediate_set](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/pki_secret_backend_intermediate_set_signed) (resource)
- [vault_pki_secret_backend_role.internal_web](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/pki_secret_backend_role) (resource)
- [vault_pki_secret_backend_root_cert.pki_root_ca](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/pki_secret_backend_root_cert) (resource)
- [vault_pki_secret_backend_root_sign_intermediate.pki_intermediate_signed](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/pki_secret_backend_root_sign_intermediate) (resource)
- [vault_policy.agent_pki](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/policy) (resource)
- [vault_policy.linux_credentials_readers](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/policy) (resource)
- [vault_policy.webapp_db_policy](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/policy) (resource)
- [aws_ami.rhel9](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) (data source)
- [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) (data source)
- [aws_route53_zone.demo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) (data source)
- [aws_route53_zone.internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) (data source)

## Outputs

The following outputs are exported:

### <a name="output_rds_endpoint"></a> [rds\_endpoint](#output\_rds\_endpoint)

Description: The endpoint of the RDS instance

### <a name="output_web_public_ip"></a> [web\_public\_ip](#output\_web\_public\_ip)

Description: The public IP of the web server

### <a name="output_website_url"></a> [website\_url](#output\_website\_url)

Description: The final secured URL of your application

<!-- markdownlint-enable -->
<!-- END_TF_DOCS -->