# OCI Resource Naming Convention

## Pattern

{resource}-{region}-{env}-{stack}-{component}-{instance}

## Examples

vcn-zrh-prod-lz-core-01
subnet-zrh-prod-lz-app-01
bastion-zrh-prod-vpn-main-01
bucket-zrh-prod-lz-backup-01

## Region Codes

eu-zurich-1   → zrh
eu-frankfurt-1 → fra
us-ashburn-1  → iad

## Environment Codes

prod | dev | test | lab

## Rules

- All lowercase
- Hyphens only (no underscores, no dots)
- Max 63 characters (OCI limit)
- Instance suffix: zero-padded 2 digits (-01, -02, ...)
- Stack examples: lz (landing-zone) | vpn | net | db | app

## Terraform

Resource names in HCL follow the same pattern (underscores for
Terraform identifiers, hyphens for OCI display names):
  name = "vcn-zrh-prod-lz-core-01"        # OCI display name
  resource "oci_core_vcn" "vcn_zrh_prod_lz_core_01" {}  # TF id
