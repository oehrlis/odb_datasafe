# OCI IAM Policies for Data Safe Management

## Overview

This document defines the IAM policies for Oracle Cloud Infrastructure (OCI)
Data Safe management in a production environment. The policies are designed to
support automated operations via service accounts while providing appropriate
access levels for different administrative roles.

**Document Version:** 1.0  
**Date:** 2026-01-13  
**Environment:** Production  
**Policy Scope:** Hierarchical compartment access from root compartment

---

## Architecture

### Compartment Structure

- **Data Safe Compartment:** Dedicated compartment for Data Safe service resources
- **Target Compartments:** Database targets may reside in various compartments across the tenancy
- **Access Pattern:** Hierarchical access with `compartment-id-in-subtree` for cross-compartment target management

### Security Principles

- **Least Privilege:** Each group has minimum required permissions
- **Separation of Duties:** Admin, Operations, and Audit roles are distinct
- **Service Account Priority:** Automation via service account for routine operations
- **Production-Grade:** Strict access controls with audit capability

---

## Groups and Roles

### 1. DataSafeAdmins

**Purpose:** Full lifecycle management of Data Safe resources  
**Use Case:** Senior DBAs and Cloud Administrators  
**Capabilities:**

- Full target lifecycle (create, register, update, delete, move)
- Connector management (create, update, delete)
- Policy and assessment configuration
- Emergency access and troubleshooting

### 2. DataSafeOperations

**Purpose:** Day-to-day operational management  
**Use Case:** DBAs and Database Operations team  
**Capabilities:**

- Target configuration updates (tags, credentials, service names)
- Target refresh and maintenance
- Policy and assessment execution
- Read-only access to connectors (use existing)

### 3. DataSafeAuditors

**Purpose:** Security compliance and audit reporting  
**Use Case:** Security Officers, Compliance Team  
**Capabilities:**

- Read-only access to all Data Safe resources
- Full access to audit trails and reports
- Assessment report viewing and export
- No modification capabilities

### 4. DataSafeServiceAccount (Dynamic Group)

**Purpose:** Automated target management and maintenance  
**Use Case:** CI/CD pipelines, automated scripts (odb_datasafe)  
**Capabilities:**

- Full target management (register, update, delete, refresh)
- Target movement between compartments
- Audit trail and assessment management
- Read-only access to connectors (use existing, cannot create)

---

## Policy Statements

### Prerequisites

1. **Create Groups** (via OCI Console or CLI):

   ```bash
   oci iam group create --name DataSafeAdmins --description "Data Safe Full Administrators"
   oci iam group create --name DataSafeOperations --description "Data Safe Operations Team"
   oci iam group create --name DataSafeAuditors --description "Data Safe Security Auditors"
   ```

2. **Create Dynamic Group** for Service Account:

   ```bash
   oci iam dynamic-group create \
     --name DataSafeServiceAccount \
     --description "Service account for automated Data Safe operations" \
     --matching-rule "ANY {instance.compartment.id = 'ocid1.compartment.oc1..xxxxx'}"
   ```

   **Matching Rule Options:**
   - By compute instance compartment: `instance.compartment.id = '<compartment-ocid>'`
   - By specific instance: `instance.id = '<instance-ocid>'`
   - By instance pool: `instance.compartment.id = '<compartment-ocid>' && resource.type = 'instance'`

3. **Variable Definitions:**
   - `<root-compartment-ocid>` - Root compartment for hierarchical access
   - `<datasafe-compartment-ocid>` - Specific compartment where Data Safe resources reside
   - `<datasafe-compartment-name>` - Name of the Data Safe compartment

---

## Policy 1: DataSafeAdmins (Full Administrative Access)

```text
# ============================================================================
# Policy Name: DataSafeAdmins-FullAccess
# Compartment: Root or Data Safe parent compartment
# ============================================================================

# Full Data Safe Management (all resources)
Allow group DataSafeAdmins to manage data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAdmins to manage data-safe-family in tenancy where all {target.compartment.id = '<datasafe-compartment-ocid>'}

# Full On-Premises Connector Management
Allow group DataSafeAdmins to manage data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAdmins to manage data-safe-private-endpoints in compartment id <datasafe-compartment-ocid>

# Compartment Management (for target organization and movement)
Allow group DataSafeAdmins to read compartments in tenancy
Allow group DataSafeAdmins to use compartments in tenancy

# Database Resource Access (for target validation and connection testing)
Allow group DataSafeAdmins to read database-family in tenancy
Allow group DataSafeAdmins to read autonomous-database-family in tenancy
Allow group DataSafeAdmins to read db-systems in tenancy
Allow group DataSafeAdmins to read autonomous-databases in tenancy

# Network Resources (for connectivity validation)
Allow group DataSafeAdmins to read virtual-network-family in tenancy
Allow group DataSafeAdmins to read vcns in tenancy
Allow group DataSafeAdmins to read subnets in tenancy

# Vault Secrets Management (for future credential management)
Allow group DataSafeAdmins to manage secret-family in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAdmins to read vaults in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAdmins to use keys in compartment id <datasafe-compartment-ocid>

# Tagging (for target organization and metadata)
Allow group DataSafeAdmins to manage tag-namespaces in tenancy
Allow group DataSafeAdmins to manage tag-defaults in tenancy
Allow group DataSafeAdmins to use tag-namespaces in tenancy
```

---

## Policy 2: DataSafeOperations (Operational Management)

```text
# ============================================================================
# Policy Name: DataSafeOperations-LimitedAccess
# Compartment: Root or Data Safe parent compartment
# ============================================================================

# Target Management (update, refresh, configure - no delete)
Allow group DataSafeOperations to use data-safe-target-databases in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to inspect data-safe-target-databases in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to use data-safe-target-databases in tenancy where target.compartment.id = '<datasafe-compartment-ocid>'

# Assessment and Audit Trail Management
Allow group DataSafeOperations to manage data-safe-security-assessments in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to manage data-safe-user-assessments in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to manage data-safe-audit-trails in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to manage data-safe-audit-policies in compartment id <datasafe-compartment-ocid>

# Discovery and Masking (for sensitive data management)
Allow group DataSafeOperations to manage data-safe-discovery-jobs in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to manage data-safe-masking-policies in compartment id <datasafe-compartment-ocid>

# Read-Only Connector Access (use existing, cannot create/delete)
Allow group DataSafeOperations to read data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to use data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>

# Compartment Navigation
Allow group DataSafeOperations to read compartments in tenancy

# Read Database Resources (for target information)
Allow group DataSafeOperations to read database-family in tenancy
Allow group DataSafeOperations to read autonomous-database-family in tenancy

# Tagging (update existing tags only)
Allow group DataSafeOperations to use tag-namespaces in tenancy

# Read Vault Secrets (for future credential retrieval)
Allow group DataSafeOperations to read secret-family in compartment id <datasafe-compartment-ocid>
Allow group DataSafeOperations to read secrets in compartment id <datasafe-compartment-ocid>
```

---

## Policy 3: DataSafeAuditors (Read-Only Audit Access)

```text
# ============================================================================
# Policy Name: DataSafeAuditors-ReadOnlyAccess
# Compartment: Root or Data Safe parent compartment
# ============================================================================

# Read-Only Access to All Data Safe Resources
Allow group DataSafeAuditors to read data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAuditors to inspect data-safe-family in compartment id <datasafe-compartment-ocid>

# Enhanced Access to Audit and Reports (read + download)
Allow group DataSafeAuditors to read data-safe-audit-trails in tenancy
Allow group DataSafeAuditors to read data-safe-audit-events in tenancy
Allow group DataSafeAuditors to read data-safe-security-assessments in tenancy
Allow group DataSafeAuditors to read data-safe-user-assessments in tenancy
Allow group DataSafeAuditors to read data-safe-reports in compartment id <datasafe-compartment-ocid>

# Compartment Navigation
Allow group DataSafeAuditors to read compartments in tenancy

# Read Database Resources (for context)
Allow group DataSafeAuditors to read database-family in tenancy
Allow group DataSafeAuditors to read autonomous-database-family in tenancy

# Read Connectors and Network (for audit context)
Allow group DataSafeAuditors to read data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>
Allow group DataSafeAuditors to read virtual-network-family in tenancy
```

---

## Policy 4: DataSafeServiceAccount (Automated Operations)

```text
# ============================================================================
# Policy Name: DataSafeServiceAccount-AutomationAccess
# Compartment: Root or Data Safe parent compartment
# Description: For automated scripts (odb_datasafe) with full target 
#              management but no connector creation
# ============================================================================

# Full Target Database Management
Allow dynamic-group DataSafeServiceAccount to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to manage data-safe-target-databases in tenancy where any {target.compartment.id = '<datasafe-compartment-ocid>', request.permission = 'DATASAFE_TARGET_DATABASE_UPDATE', request.permission = 'DATASAFE_TARGET_DATABASE_DELETE', request.permission = 'DATASAFE_TARGET_DATABASE_CREATE', request.permission = 'DATASAFE_TARGET_DATABASE_MOVE', request.permission = 'DATASAFE_TARGET_DATABASE_REFRESH'}

# Assessment and Audit Management
Allow dynamic-group DataSafeServiceAccount to manage data-safe-security-assessments in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to manage data-safe-user-assessments in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to manage data-safe-audit-trails in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to manage data-safe-audit-policies in compartment id <datasafe-compartment-ocid>

# Discovery and Masking
Allow dynamic-group DataSafeServiceAccount to manage data-safe-discovery-jobs in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to manage data-safe-masking-policies in compartment id <datasafe-compartment-ocid>

# Read-Only Connector Access (use existing, CANNOT create/delete)
Allow dynamic-group DataSafeServiceAccount to read data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to use data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to inspect data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>

# Compartment Management (for target movement and organization)
Allow dynamic-group DataSafeServiceAccount to read compartments in tenancy
Allow dynamic-group DataSafeServiceAccount to use compartments in tenancy

# Database Resource Access (for target validation)
Allow dynamic-group DataSafeServiceAccount to read database-family in tenancy
Allow dynamic-group DataSafeServiceAccount to read autonomous-database-family in tenancy
Allow dynamic-group DataSafeServiceAccount to read db-systems in tenancy

# Network Resources (for connectivity validation)
Allow dynamic-group DataSafeServiceAccount to read virtual-network-family in tenancy

# Tagging (for target organization)
Allow dynamic-group DataSafeServiceAccount to use tag-namespaces in tenancy

# Vault Secrets (for future credential retrieval)
Allow dynamic-group DataSafeServiceAccount to read secret-family in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to read secrets in compartment id <datasafe-compartment-ocid>
Allow dynamic-group DataSafeServiceAccount to use keys in compartment id <datasafe-compartment-ocid>
```

---

## Additional Considerations for Production

### 1. Policy Conditions

Add conditions to policies for enhanced security:

```text
# Example: Restrict by IP address
Allow group DataSafeOperations to use data-safe-target-databases in compartment id <datasafe-compartment-ocid> where request.networkSource.name='CorporateNetwork'

# Example: Restrict by time window (for maintenance windows)
Allow dynamic-group DataSafeServiceAccount to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where request.user.mfaAuthenticated='true'

# Example: Restrict delete operations to specific times
Allow group DataSafeAdmins to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where any {request.operation != 'DeleteTargetDatabase', request.operation = 'DeleteTargetDatabase' && request.user.mfaAuthenticated='true'}
```

### 2. MFA Requirements

For production environments, enforce MFA for sensitive operations:

```text
# Require MFA for deletion operations (Admin group)
Allow group DataSafeAdmins to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where any {request.permission != 'DATASAFE_TARGET_DATABASE_DELETE', request.user.mfaAuthenticated='true'}
```

### 3. Audit Logging

Enable audit logging for all Data Safe operations:

```text
# Ensure audit logs are retained
# Configure via OCI Console: Governance & Administration > Audit
# Retention: Minimum 365 days for production
```

### 4. Network Source Restrictions

Create network sources for restricted access:

```text
# Create network source
oci iam network-source create \
  --name CorporateNetwork \
  --public-source-list '["203.0.113.0/24", "198.51.100.0/24"]'

# Apply to policies
Allow group DataSafeAdmins to manage data-safe-family in compartment id <datasafe-compartment-ocid> where request.networkSource.name='CorporateNetwork'
```

### 5. Emergency Access

Create a break-glass admin policy with separate group:

```text
# Emergency access group (use sparingly)
Allow group DataSafeEmergency to manage data-safe-family in tenancy

# Monitor usage strictly via audit logs
```

---

## Policy Deployment Guide

### Step 1: Prepare Environment

1. Identify compartment OCIDs:

   ```bash
   # List all compartments
   oci iam compartment list --all --compartment-id-in-subtree true
   
   # Get Data Safe compartment OCID
   export DATASAFE_COMP=$(oci iam compartment list --all \
     --query "data[?name=='<datasafe-compartment-name>'].id | [0]" \
     --raw-output)
   ```

2. Create groups:

   ```bash
   oci iam group create --name DataSafeAdmins --description "Data Safe Full Administrators"
   oci iam group create --name DataSafeOperations --description "Data Safe Operations Team"
   oci iam group create --name DataSafeAuditors --description "Data Safe Security Auditors"
   ```

3. Create dynamic group for service account:

   ```bash
   # Replace <compartment-ocid> with your compute compartment
   oci iam dynamic-group create \
     --name DataSafeServiceAccount \
     --description "Service account for automated Data Safe operations" \
     --matching-rule "instance.compartment.id = '<compartment-ocid>'"
   ```

### Step 2: Create Policies

1. Create policy files (one per group):
   - `datasafe-admins-policy.txt`
   - `datasafe-operations-policy.txt`
   - `datasafe-auditors-policy.txt`
   - `datasafe-serviceaccount-policy.txt`

2. Deploy policies:

   ```bash
   # Admin policy
   oci iam policy create \
     --compartment-id <root-compartment-ocid> \
     --name DataSafeAdmins-FullAccess \
     --description "Full Data Safe administration access" \
     --statements file://datasafe-admins-policy.txt

   # Operations policy
   oci iam policy create \
     --compartment-id <root-compartment-ocid> \
     --name DataSafeOperations-LimitedAccess \
     --description "Data Safe operational access" \
     --statements file://datasafe-operations-policy.txt

   # Auditors policy
   oci iam policy create \
     --compartment-id <root-compartment-ocid> \
     --name DataSafeAuditors-ReadOnlyAccess \
     --description "Data Safe audit and reporting access" \
     --statements file://datasafe-auditors-policy.txt

   # Service account policy
   oci iam policy create \
     --compartment-id <root-compartment-ocid> \
     --name DataSafeServiceAccount-AutomationAccess \
     --description "Data Safe automation access for service accounts" \
     --statements file://datasafe-serviceaccount-policy.txt
   ```

### Step 3: Add Users to Groups

```bash
# Get user OCID
USER_OCID=$(oci iam user list --query "data[?name=='john.doe@example.com'].id | [0]" --raw-output)

# Add to group
oci iam group add-user \
  --user-id $USER_OCID \
  --group-id $(oci iam group list --query "data[?name=='DataSafeAdmins'].id | [0]" --raw-output)
```

### Step 4: Verify Policies

```bash
# List policies
oci iam policy list --compartment-id <root-compartment-ocid>

# Get policy details
oci iam policy get --policy-id <policy-ocid>

# Test access with specific user
oci data-safe target-database list \
  --compartment-id $DATASAFE_COMP \
  --auth api_key \
  --profile <user-profile>
```

---

## Testing and Validation

### 1. Service Account Testing

Test automated operations with the service account:

```bash
# SSH to compute instance (or run from compute)
# Service account should work automatically via instance principal

# Test target list
oci data-safe target-database list \
  --compartment-id $DATASAFE_COMP \
  --compartment-id-in-subtree true \
  --auth instance_principal

# Test target update
oci data-safe target-database update \
  --target-database-id <target-ocid> \
  --freeform-tags '{"Environment":"prod"}' \
  --auth instance_principal
```

### 2. Operations Testing

Test with DataSafeOperations user:

```bash
# Should succeed: List targets
oci data-safe target-database list --compartment-id $DATASAFE_COMP

# Should succeed: Update target
oci data-safe target-database update --target-database-id <target-ocid> --freeform-tags '{}'

# Should fail: Create connector (read-only access)
oci data-safe on-prem-connector create --compartment-id $DATASAFE_COMP
# Expected: Authorization failed
```

### 3. Auditor Testing

Test with DataSafeAuditors user:

```bash
# Should succeed: Read targets
oci data-safe target-database list --compartment-id $DATASAFE_COMP

# Should succeed: Read audit trails
oci data-safe audit-trail list --compartment-id $DATASAFE_COMP

# Should fail: Update target
oci data-safe target-database update --target-database-id <target-ocid> --freeform-tags '{}'
# Expected: Authorization failed
```

---

## Troubleshooting

### Common Issues

1. **"Authorization failed" errors:**
   - Verify user is in correct group: `oci iam user list-groups --user-id <user-ocid>`
   - Check policy syntax and compartment OCIDs
   - Verify policy is in correct compartment (root or parent)
   - Wait 5-10 minutes for policy propagation

2. **Service account cannot access resources:**
   - Verify dynamic group matching rule
   - Confirm instance is in specified compartment
   - Check instance principal authentication is enabled
   - Verify policies are at tenancy or parent compartment level

3. **Cannot access targets in other compartments:**
   - Ensure policies use `tenancy` or `compartment-id-in-subtree true`
   - Verify hierarchical compartment access is granted
   - Check target compartment structure

4. **Cannot use vault secrets:**
   - Verify vault policies are in place
   - Check secret compartment matches policy
   - Ensure key permissions are granted

### Policy Validation

```bash
# Check effective permissions for a user
oci iam policy list --compartment-id <root-compartment> | jq '.data[].statements[]'

# Validate dynamic group membership
oci iam dynamic-group get --dynamic-group-id <dynamic-group-ocid>

# Test specific permission
oci data-safe target-database list --compartment-id $DATASAFE_COMP --debug
```

---

## Maintenance and Review

### Regular Activities

1. **Quarterly Policy Review:**
   - Review group memberships
   - Audit unused permissions
   - Update policies based on operational needs

2. **Audit Log Analysis:**
   - Monitor failed authorization attempts
   - Review Data Safe operation patterns
   - Identify potential security issues

3. **Group Membership Audit:**
   - Remove inactive users
   - Verify role assignments
   - Update based on organizational changes

### Policy Update Process

1. Test policy changes in development environment
2. Document changes in this file
3. Get approval from security team
4. Apply during maintenance window
5. Verify with test users
6. Monitor audit logs for issues

---

## References

- [OCI IAM Policies](https://docs.oracle.com/en-iaas/Content/Identity/Concepts/policies.htm)
- [OCI Data Safe Policies](https://docs.oracle.com/en-iaas/data-safe/doc/iam-policies.html)
- [OCI Dynamic Groups](https://docs.oracle.com/en-iaas/Content/Identity/Tasks/managingdynamicgroups.htm)
- [OCI Policy Reference](https://docs.oracle.com/en-iaas/Content/Identity/policyreference/policyreference.htm)
- [odb_datasafe Documentation](../README.md)

---

## Change Log

| Date       | Version | Author        | Changes                                |
|------------|---------|---------------|----------------------------------------|
| 2026-01-13 | 1.0.0   | Stefan Oehrli | Initial policy document for production |

---

## Contact

For questions or policy change requests, contact:

- **Data Safe Admin Team:** <datasafe-admins@example.com>
- **Security Team:** <security@example.com>
- **Cloud Operations:** <cloudops@example.com>
