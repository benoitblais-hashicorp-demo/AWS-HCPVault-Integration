# AGENTS.md for Terraform Project

This file provides instructions for AI coding agents working on this Terraform Project.

## Project Overview

This project provides an end-to-end Terraform architecture demonstrating HashiCorp Vault integrations.
It deploys core AWS infrastructure (VPC, EC2, RDS, ALB) focused on a fully standardized, dynamic Vault architecture.
Vault manages application and database secrets, while Linux VM credentials are stored in KV and public certificates are managed by AWS ACM.
The file `docs/SPECIFICATION.md` is the source of truth for architecture decisions, requirements, and acceptance criteria.

### Architecture Decisions

- Do not implement Vault OS dynamic credentials integration (`vault-plugin-secrets-os`) in this repository.
- Do not implement Vault External CA orchestration (`pki-external-ca`) for public certificates.
- Store Linux VM passwords in a Vault KV mount and retrieve them securely for operational use.
- Use AWS Certificate Manager (ACM) for public-facing ALB certificates.
- Vault PKI can still be used for internal/private certificate use cases where appropriate.

## Module and Repository Structure

Organize your Terraform project with standard root-module file names and a single dynamic architecture:

```text
├── .gitignore
├── LICENSE
├── README.md
├── main.tf
├── outputs.tf
├── providers.tf
├── variables.tf
├── versions.tf
├── docs/
│   ├── CODE_OF_CONDUCT.md
│   ├── CONTRIBUTING.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── README_footer.md
│   ├── README_header.md
│   ├── SPECIFICATION.md
│   ├── SECURITY.md
```

### Required Files and Directories

- `README.md` – Required in the root module. Generated automatically (e.g., via Terraform-Docs). Do not edit manually.
- `docs/SPECIFICATION.md` - Source of truth for architecture decisions, implementation requirements, and acceptance criteria.
- `docs/README_header.md` - Describe the purpose of the code and provide required context.
- `docs/README_footer.md` - Provide links to external documentation used to generate the code.
- `main.tf` – Root module resources, modules, and data sources placed next to the resources that consume them.
- `outputs.tf` – Root module outputs (alphabetical order).
- `providers.tf` – Provider configurations.
- `variables.tf` – Global input variable definitions (alphabetical order with required variables at the top).
- `versions.tf` - Terraform version and provider requirements.

### Main.tf Layout

- `main.tf` must include a dedicated `Vault Core Configuration` section for shared Vault namespaces, engines, and auth backends.
- Resource-specific sections such as webserver or database should only define consumer-side policies, roles, and stored secrets that use the core Vault configuration.

## Tools and Frameworks

- AI Agents should format their generated HCL optimally as local `terraform fmt`, `terraform init`, and `terraform validate` cannot be run directly during the session due to the VCS-driven workflow.
- Formatting and CI/CD validation are handled by an automated VCS workflow, meaning the Agent does not need to run a local linter or validation operations locally. Do your best to output valid HCL code and do not try to run Terraform commands in the terminal.
- Use `terraform-docs` to generate the `README.md` file using the header and footer (you don't need to do this manually if the CI does it, but you must create the header/footer files).

## README_header.md

When editing or creating `docs/README_header.md`, ensure it contains:

- A description of the general purpose of the code.
- A `Permissions` section containing the permissions required to provision resources for each provider.
- An `Authentications` section containing the authentication details required for each provider.
- A `Features` section containing key features managed by the code.

## README_footer.md

When editing or creating `docs/README_footer.md`, ensure it contains:

- An `External Documentation` section providing links to relevant external documentation used to develop the code (e.g., HashiCorp Vault Provider docs, Vault KV Secrets Engine docs, Vault JWT Auth Method, AWS ACM docs, and AWS Provider docs).

## Code Guidelines

Refer to CONTRIBUTING.md for general coding guidelines. HashiCorp's Terraform style guide should be applied for all code generated.

## Resource Naming

- Use descriptive nouns separated by underscores.
- Do not include the resource type in the resource name.
- Wrap resource type and name in double quotes.
- Example: `resource "aws_eks_cluster" "main"` not `resource "aws_eks_cluster" "eks_main"`.

## Version Management

- Prefer the pessimistic constraint operator (`~>`) for modules and providers to allow safe updates within a compatible version range.
- Avoid using only the equals (`=`) operator unless you must lock to a single version for reproducibility or known issues.
- Pin the Terraform version using `required_version` in the `terraform` block.

## Provider Configuration

- Always include a default provider configuration.
- Define all providers in the same file (`providers.tf`).
- Define the default provider first, then aliased providers.
- Use `alias` as the first parameter in non-default provider blocks.

## Security and Secrets

- Never commit `.terraform` directories or local state files.
- The project leverages dynamic provider credentials natively supported by HCP Terraform workspaces via the VCS workflow. No static Vault token is used.
- The Vault provider authenticates via JWT dynamic credentials. Set `VAULT_ADDR` as a workspace variable pointing to the HCP Vault cluster endpoint.
- Access secrets securely via workspace variables or Vault lookups.
- Apply least-privilege IAM and Vault policies for all identities.
- Avoid exposing credentials in outputs, logs, or user data where possible.
- Set `sensitive = true` for sensitive variables across all definitions.

## State Management

- State storage is managed natively by HCP Terraform workspaces. Data sharing between configurations relies on standard data sources or `tfe_outputs` where cross-workspace values are required.
