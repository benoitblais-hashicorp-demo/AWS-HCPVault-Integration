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
2. **Demonstrate Dynamic OS Access:**
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
   * Connect directly to the AWS RDS instance using these credentials (e.g., using `psql`, PGAdmin or DBeaver). Provide the RDS Endpoint output from Terraform as the host.
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

The `vault` provider must be configured to communicate with your HashiCorp Vault cluster.

* **HCP Terraform / JWT Auth (Recommended)**: Configure Vault to trust HCP Terraform workspace identities via JWT authentication.
* **Environment Variables**: Provide the Vault address and token for local runs.

  ```bash
  export VAULT_ADDR="https://vault.example.com:8200"
   export VAULT_TOKEN="<your-vault-token>"
  ```
