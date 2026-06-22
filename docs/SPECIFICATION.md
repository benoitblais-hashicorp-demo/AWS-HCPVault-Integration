# AWS and HCP Vault Integration Specification

## 1. Purpose

Define the target architecture and implementation requirements for a Terraform-based demonstration integrating AWS infrastructure with HCP Vault for secure secret management.

This specification is the source of truth for implementation behavior, guardrails, and acceptance criteria.

## 2. Scope

### 2.1 In Scope

- Provision AWS infrastructure with Terraform:
  - VPC and subnets
  - EC2 Linux VM for application hosting
  - RDS PostgreSQL
  - ALB for public ingress
  - Route53 records
- Integrate HCP Vault for secret management:
  - Use a single Vault namespace for the demo
  - Store Linux VM password in Vault KV v2
  - Configure Vault Database Secrets Engine for dynamic PostgreSQL credentials
  - Support internal/private TLS use cases with Vault PKI (root and intermediate)
- Use AWS ACM for public-facing certificate on ALB.

### 2.2 Out of Scope

- Vault OS dynamic credentials integration using vault-plugin-secrets-os
- Vault External CA orchestration using pki-external-ca
- Static-vs-dynamic comparison track
- Custom Vault plugin installation in HCP Vault

## 3. Platform Constraints

- Vault platform: HCP Vault Dedicated
- HCP Vault limitation: no user-managed plugin binary upload/registration
- Public certificate management must use AWS ACM for this project

## 4. Architecture Requirements

### 4.1 AWS Infrastructure

- VPC with public and private subnets across at least two availability zones.
- ALB exposes HTTPS endpoint and forwards traffic to EC2 target(s).
- EC2 instance hosts application workload.
- RDS PostgreSQL is reachable per security group policy defined for demo operations.
- Route53 records map public hostname to ALB and internal hostname(s) as needed.

### 4.2 Vault Integration

- Demo Vault namespace path: `demo_platform` by default, configurable via input variable.
- Namespace values must match the pattern `^demo_[a-z0-9_]+$`.
- KV secrets engine stores Linux VM password material in `kvv2`.
- Vault PKI uses `pki-root` and `pki-intermediate` for internal/private certificate issuance.
- Vault AWS auth method is enabled inside the demo namespace for workload authentication.
- Terraform must not hardcode plaintext secrets in source files.
- Vault Database Secrets Engine issues short-lived database credentials for application/demo access.
- Optional: Vault PKI may issue internal certificates for private trust domains.

### 4.3 Public TLS

- AWS ACM provides certificate for the public ALB listener.
- ALB HTTPS listener references ACM certificate ARN.

## 5. Repository and File Conventions

Root module uses canonical Terraform filenames:

- main.tf: root resources and module calls
- variables.tf: all input variables (required first, then optional/alphabetical)
- outputs.tf: outputs (alphabetical)
- providers.tf: provider configuration
- versions.tf: terraform and provider version constraints

`main.tf` should include a dedicated `Vault Core Configuration` section for shared Vault namespaces, PKI mounts, KV v2, auth backends, and database engine configuration.

Shared data sources are defined in `main.tf` and placed next to the resources that consume them.

Consumer sections such as webserver or database should only define policies, roles, and secret material that depend on the core Vault configuration.

Vault resources expected inside the namespace include:

- pki-root
- pki-intermediate
- kvv2
- aws auth method
- database secrets engine
- demo-specific ACL policies

Documentation files:

- docs/README_header.md
- docs/README_footer.md
- docs/SPECIFICATION.md (this file)

## 6. Security Requirements

- Mark sensitive variables with sensitive = true.
- Do not commit local Terraform state or .terraform directories.
- Secrets must be passed via secure workspace variables or Vault lookups.
- Least privilege IAM and Vault policies should be applied.
- Avoid exposing credentials in outputs, logs, or user_data where possible.

## 7. Functional Requirements

### FR-1 Infrastructure Provisioning

Terraform apply provisions VPC, ALB, EC2, RDS, and DNS resources required for the demo.

### FR-2 Linux Password in Vault KV

Linux VM password is stored in Vault KV at a documented path and retrievable by authorized principals.

### FR-3 Dynamic DB Credentials

Vault database role issues ephemeral PostgreSQL credentials with defined TTL.

### FR-4 Public HTTPS

Public application URL is served through ALB HTTPS using AWS ACM certificate.

### FR-5 Internal PKI (Optional)

When enabled, internal certificates can be issued by Vault PKI for private trust scenarios.

## 8. Non-Functional Requirements

- Maintainable Terraform structure and naming consistency.
- Compatibility with HCP Terraform / VCS-driven CI workflow.
- Clear, reproducible demo steps in documentation.
- No reliance on unsupported HCP Vault plugin installation workflows.

## 9. Acceptance Criteria

### AC-1

Repository follows canonical root file naming and dynamic-only architecture.

### AC-2

No resource blocks or documentation references rely on vault-plugin-secrets-os.

### AC-3

No resource blocks or documentation references rely on pki-external-ca for public certs.

### AC-4

Public ALB endpoint presents a valid ACM-backed certificate.

### AC-5

Vault KV path for Linux password is documented and accessible with proper policy.

### AC-6

Vault database dynamic credentials can be generated and used to connect to RDS within TTL.

## 10. Documentation Requirements

- README content must reflect dynamic-only architecture.
- Demo instructions must describe:
  - Retrieving Linux VM password from Vault KV
  - Generating dynamic database credentials from Vault
  - Verifying public certificate via AWS ACM on ALB
- Remove static-track instructions and references.

## 11. Risks and Mitigations

- Risk: Secret exposure through bootstrap scripts.
  - Mitigation: minimize secret rendering and rotate credentials after bootstrap.
- Risk: HCP Vault feature mismatch.
  - Mitigation: rely only on supported engines and document exclusions.
- Risk: Misaligned docs and code.
  - Mitigation: maintain this specification and regenerate README from docs inputs.

## 12. Change Control

Any change affecting architecture decisions in this file requires synchronized updates to:

- AGENTS.md
- docs/README_header.md
- Terraform implementation in root module files
