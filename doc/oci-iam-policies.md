# OCI IAM Policies for Data Safe Management

## Overview

This document defines the IAM policies for Oracle Cloud Infrastructure (OCI)
Data Safe management in a production environment. The policies are designed to
support automated operations via service accounts while providing appropriate
access levels for different administrative roles.

**Document Version:** 1.0.0
**Date:** 13.01.2026
**Environment:** Production  
**Policy Scope:** Hierarchical compartment access from root compartment

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

## Groups and Roles

### Data Safe Admin Group

**Group Name:** `grp-ds-admin`  
**Description:** Data Safe administration group with full administrative rights
across OCI resources, enabling management of all cloud services, configurations,
and security policies, excluding Identity and access management configurations.  
**Use Case:** Senior DBAs and Cloud Administrators  
**Capabilities:**

- Full target lifecycle (create, register, update, delete, move)
- Connector management (create, update, delete)
- Policy and assessment configuration
- Emergency access and troubleshooting

### Data Safe Operation Group

**Group Name:** `grp-ds-operation`  
**Description:** Data Safe operations group with day-to-day operational management
capabilities for target configuration, maintenance, and assessment execution.  
**Use Case:** DBAs and Database Operations team  
**Capabilities:**

- Target configuration updates (tags, credentials, service names)
- Target refresh and maintenance
- Policy and assessment execution
- Read-only access to connectors (use existing)

### Data Safe Auditor Group

**Group Name:** `grp-ds-auditor`  
**Description:** Data Safe auditor group with read-only access for security
compliance and audit reporting, enabling comprehensive monitoring without modification
capabilities.  
**Use Case:** Security Officers, Compliance Team  
**Capabilities:**

- Read-only access to all Data Safe resources
- Full access to audit trails and reports
- Assessment report viewing and export
- No modification capabilities

### Data Safe Service Account Group

**Group Name:** `grp-ds-service`  
**Description:** Data Safe service account group for automated target management,
maintenance operations, and CI/CD pipeline integration.  
**Use Case:** CI/CD pipelines, automated scripts (odb_datasafe)  
**Capabilities:**

- Full target management (register, update, delete, refresh)
- Target movement between compartments
- Audit trail and assessment management
- Read-only access to connectors (use existing, cannot create)

## Policy Statements

### Prerequisites

1. **Create Groups** (via OCI Console or CLI):

   ```bash
   oci iam group create --name grp-ds-admin --description "Data Safe administration group with full administrative rights across OCI resources, enabling management of all cloud services, configurations, and security policies, excluding Identity and access management configurations."
   oci iam group create --name grp-ds-operation --description "Data Safe operations group with day-to-day operational management capabilities for target configuration, maintenance, and assessment execution."
   oci iam group create --name grp-ds-auditor --description "Data Safe auditor group with read-only access for security compliance and audit reporting, enabling comprehensive monitoring without modification capabilities."
   oci iam group create --name grp-ds-service --description "Data Safe service account group for automated target management, maintenance operations, and CI/CD pipeline integration."
   ```

2. **Variable Definitions:**
   - `<root-compartment-ocid>` - Root compartment for hierarchical access
   - `<datasafe-compartment-ocid>` - Specific compartment where Data Safe resources reside
   - `<datasafe-compartment-name>` - Name of the Data Safe compartment

## Data Safe Admin Group Policy

**Policy File:** `pcy-ds-admin.json`

```text
# ============================================================================
# Policy Name: pcy-ds-admin
# Compartment: Root or Data Safe parent compartment
# Description: Policy to allow grp-ds-admin group users to manage all Data Safe
#              resources, connectors, and security configurations across OCI
# ============================================================================

# Full Data Safe Management (all resources)
Allow group grp-ds-admin to manage data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-admin to manage data-safe-family in tenancy

# Note: data-safe-family includes all Data Safe resources including:
# - target-databases, security-assessments, user-assessments
# - data-safe-private-endpoints, onprem-connectors
# - data-safe-sensitive-data-models, data-safe-masking-policies
# - data-safe-audit-profiles, data-safe-audit-trails, data-safe-audit-events
# - and all other Data Safe resources

# Compartment Management (for target organization and movement)
Allow group grp-ds-admin to read compartments in tenancy
Allow group grp-ds-admin to use compartments in tenancy

# Database Resource Access (for target validation and connection testing)
Allow group grp-ds-admin to read database-family in tenancy
Allow group grp-ds-admin to read autonomous-database-family in tenancy
Allow group grp-ds-admin to read db-systems in tenancy
Allow group grp-ds-admin to read autonomous-databases in tenancy

# Network Resources (for connectivity validation)
Allow group grp-ds-admin to read virtual-network-family in tenancy
Allow group grp-ds-admin to read vcns in tenancy
Allow group grp-ds-admin to read subnets in tenancy

# Vault Secrets Management (for future credential management)
Allow group grp-ds-admin to manage secret-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-admin to read vaults in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-admin to use keys in compartment id <datasafe-compartment-ocid>

# Tagging (for target organization and metadata)
Allow group grp-ds-admin to manage tag-namespaces in tenancy
Allow group grp-ds-admin to manage tag-defaults in tenancy
Allow group grp-ds-admin to use tag-namespaces in tenancy
```

## Data Safe Operation Group Policy

**Policy File:** `pcy-ds-operation.json`

```text
# ============================================================================
# Policy Name: pcy-ds-operation
# Compartment: Root or Data Safe parent compartment
# Description: Policy to allow grp-ds-operation group users to use and inspect
#              Data Safe resources for day-to-day operations
# ============================================================================

# Data Safe Operations (use and inspect - no create/delete)
Allow group grp-ds-operation to use data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-operation to inspect data-safe-family in compartment id <datasafe-compartment-ocid>

# Note: data-safe-family includes all Data Safe resources
# 'use' verb allows updating existing resources but not creating/deleting
# 'inspect' verb allows detailed read access

# Compartment Navigation
Allow group grp-ds-operation to read compartments in tenancy

# Read Database Resources (for target information)
Allow group grp-ds-operation to read database-family in tenancy
Allow group grp-ds-operation to read autonomous-database-family in tenancy

# Tagging (update existing tags only)
Allow group grp-ds-operation to use tag-namespaces in tenancy

# Read Vault Secrets (for future credential retrieval)
Allow group grp-ds-operation to read secret-family in compartment id <datasafe-compartment-ocid>
```

## Data Safe Auditor Group Policy

**Policy File:** `pcy-ds-auditor.json`

```text
# ============================================================================
# Policy Name: pcy-ds-auditor
# Compartment: Root or Data Safe parent compartment
# Description: Policy to allow grp-ds-auditor group users to read and inspect
#              all Data Safe resources for security compliance and audit
#              reporting without modification capabilities
# ============================================================================

# Read-Only Access to All Data Safe Resources
Allow group grp-ds-auditor to read data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-auditor to inspect data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-auditor to read data-safe-family in tenancy

# Note: data-safe-family includes all Data Safe resources including:
# - target-databases, audit-trails, audit-events
# - security-assessments, user-assessments, reports
# - onprem-connectors, private-endpoints, and all other Data Safe resources

# Compartment Navigation
Allow group grp-ds-auditor to read compartments in tenancy

# Read Database Resources (for context)
Allow group grp-ds-auditor to read database-family in tenancy
Allow group grp-ds-auditor to read autonomous-database-family in tenancy

# Read Network Resources (for audit context)
Allow group grp-ds-auditor to read virtual-network-family in tenancy
```

## Data Safe Service Account Group Policy

**Policy File:** `pcy-ds-service.json`

```text
# ============================================================================
# Policy Name: pcy-ds-service
# Compartment: Root or Data Safe parent compartment
# Description: Policy to allow grp-ds-service group to manage automated
#              target operations, assessments, and audit trails for CI/CD
#              pipelines and service/functional user accounts
# ============================================================================

# Full Data Safe Management
Allow group grp-ds-service to manage data-safe-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-service to manage data-safe-family in tenancy

# Note: data-safe-family includes all Data Safe resources including:
# - target-databases (register, update, delete, move)
# - security-assessments, user-assessments, audit-trails
# - discovery-jobs, masking-policies
# - onprem-connectors (read/use only, cannot create)
# - and all other Data Safe resources

# Compartment Management (for target movement and organization)
Allow group grp-ds-service to read compartments in tenancy
Allow group grp-ds-service to use compartments in tenancy

# Database Resource Access (for target validation)
Allow group grp-ds-service to read database-family in tenancy
Allow group grp-ds-service to read autonomous-database-family in tenancy
Allow group grp-ds-service to read db-systems in tenancy

# Network Resources (for connectivity validation)
Allow group grp-ds-service to read virtual-network-family in tenancy

# Tagging (for target organization)
Allow group grp-ds-service to use tag-namespaces in tenancy

# Vault Secrets (for future credential retrieval)
Allow group grp-ds-service to read secret-family in compartment id <datasafe-compartment-ocid>
Allow group grp-ds-service to use keys in compartment id <datasafe-compartment-ocid>
```

## Additional Considerations for Production

### 1. Policy Conditions

Add conditions to policies for enhanced security:

```text
# Example: Restrict by IP address
Allow group grp-ds-operation to use data-safe-target-databases in compartment id <datasafe-compartment-ocid> where request.networkSource.name='CorporateNetwork'

# Example: Restrict by time window (for maintenance windows)
Allow group grp-ds-service to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where request.user.mfaAuthenticated='true'

# Example: Restrict delete operations to specific times
Allow group grp-ds-admin to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where any {request.operation != 'DeleteTargetDatabase', request.operation = 'DeleteTargetDatabase' && request.user.mfaAuthenticated='true'}
```

### 2. MFA Requirements

For production environments, enforce MFA for sensitive operations:

```text
# Require MFA for deletion operations (Admin group)
Allow group grp-ds-admin to manage data-safe-target-databases in compartment id <datasafe-compartment-ocid> where any {request.permission != 'DATASAFE_TARGET_DATABASE_DELETE', request.user.mfaAuthenticated='true'}
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
Allow group grp-ds-admin to manage data-safe-family in compartment id <datasafe-compartment-ocid> where request.networkSource.name='CorporateNetwork'
```

### 5. Emergency Access

Create a break-glass admin policy with separate group:

```text
# Emergency access group (use sparingly)
Allow group DataSafeEmergency to manage data-safe-family in tenancy

# Monitor usage strictly via audit logs
```

## Policy Deployment Guide

### Step 1: Prepare Environment

1. Identify compartment OCIDs:

   ```bash
   # Set root compartment OCID (tenancy OCID)
   export ROOT_COMP_OCID="ocid1.tenancy.oc1..aaaaaaaa..."
   
   # List all compartments
   oci iam compartment list --all --compartment-id-in-subtree true
   
   # Get Data Safe compartment OCID
   export DATASAFE_COMP=$(oci iam compartment list --all \
     --query "data[?name=='<datasafe-compartment-name>'].id | [0]" \
     --raw-output)
   ```

2. Create groups:

   ```bash
   oci iam group create --name grp-ds-admin --description "Data Safe administration group with full administrative rights across OCI resources, enabling management of all cloud services, configurations, and security policies, excluding Identity and access management configurations."
   oci iam group create --name grp-ds-operation --description "Data Safe operations group with day-to-day operational management capabilities for target configuration, maintenance, and assessment execution."
   oci iam group create --name grp-ds-auditor --description "Data Safe auditor group with read-only access for security compliance and audit reporting, enabling comprehensive monitoring without modification capabilities."
   oci iam group create --name grp-ds-service --description "Data Safe service account group for automated target management, maintenance operations, and CI/CD pipeline integration."
   ```

### Step 2: Create Policies

1. Policy JSON template files are provided in the `etc/` folder:
   - `etc/pcy-ds-admin.json.example`
   - `etc/pcy-ds-operation.json.example`
   - `etc/pcy-ds-auditor.json.example`
   - `etc/pcy-ds-service.json.example`

   **IMPORTANT:** The JSON template files contain ONLY valid JSON arrays of strings -
   no comments, no blank lines outside the array.

   Example for `pcy-ds-admin.json`:

   ```json
   [
     "Allow group grp-ds-admin to manage data-safe-family in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to manage data-safe-family in tenancy where all {target.compartment.id = '<datasafe-compartment-ocid>'}",
     "Allow group grp-ds-admin to manage data-safe-on-prem-connectors in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to manage data-safe-private-endpoints in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to read compartments in tenancy",
     "Allow group grp-ds-admin to use compartments in tenancy",
     "Allow group grp-ds-admin to read database-family in tenancy",
     "Allow group grp-ds-admin to read autonomous-database-family in tenancy",
     "Allow group grp-ds-admin to read db-systems in tenancy",
     "Allow group grp-ds-admin to read autonomous-databases in tenancy",
     "Allow group grp-ds-admin to read virtual-network-family in tenancy",
     "Allow group grp-ds-admin to read vcns in tenancy",
     "Allow group grp-ds-admin to read subnets in tenancy",
     "Allow group grp-ds-admin to manage secret-family in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to read vaults in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to use keys in compartment id <datasafe-compartment-ocid>",
     "Allow group grp-ds-admin to manage tag-namespaces in tenancy",
     "Allow group grp-ds-admin to manage tag-defaults in tenancy",
     "Allow group grp-ds-admin to use tag-namespaces in tenancy"
   ]
   ```

   **Helper script to create JSON from policy statements:**

   ```bash
   # Extract policy statements from documentation and convert to JSON array
   # Remove comments, blank lines, and format as JSON
   grep "^Allow group grp-ds-admin" pcy-ds-admin.txt | \
     jq -R -s -c 'split("\n") | map(select(length > 0))' > pcy-ds-admin.json
   ```

   **Replace placeholders with actual OCIDs:**

   ```bash
   # Set your Data Safe compartment OCID
   export DATASAFE_COMP_OCID="ocid1.compartment.oc1..aaaaaaaa..."
   
   # Create policy files from templates with actual OCID
   sed "s/<datasafe-compartment-ocid>/${DATASAFE_COMP_OCID}/g" etc/pcy-ds-admin.json.example > etc/pcy-ds-admin.json
   sed "s/<datasafe-compartment-ocid>/${DATASAFE_COMP_OCID}/g" etc/pcy-ds-operation.json.example > etc/pcy-ds-operation.json
   sed "s/<datasafe-compartment-ocid>/${DATASAFE_COMP_OCID}/g" etc/pcy-ds-auditor.json.example > etc/pcy-ds-auditor.json
   sed "s/<datasafe-compartment-ocid>/${DATASAFE_COMP_OCID}/g" etc/pcy-ds-service.json.example > etc/pcy-ds-service.json
   ```

2. Deploy policies:

   ```bash
   # Admin policy
   oci iam policy create \
     --compartment-id $ROOT_COMP_OCID \
     --name pcy-ds-admin \
     --description "Policy to allow grp-ds-admin group users to manage all Data Safe resources, connectors, and security configurations across OCI" \
     --statements file://etc/pcy-ds-admin.json

   # Operations policy
   oci iam policy create \
     --compartment-id $ROOT_COMP_OCID \
     --name pcy-ds-operation \
     --description "Policy to allow grp-ds-operation group users to manage day-to-day operations including target configuration, assessments, and audit trails" \
     --statements file://etc/pcy-ds-operation.json

   # Auditors policy
   oci iam policy create \
     --compartment-id $ROOT_COMP_OCID \
     --name pcy-ds-auditor \
     --description "Policy to allow grp-ds-auditor group users to read and inspect all Data Safe resources for security compliance and audit reporting" \
     --statements file://etc/pcy-ds-auditor.json

   # Service account policy
   oci iam policy create \
     --compartment-id $ROOT_COMP_OCID \
     --name pcy-ds-service \
     --description "Policy to allow grp-ds-service group to manage automated target operations, assessments, and audit trails for CI/CD pipelines" \
     --statements file://etc/pcy-ds-service.json
   ```

   **Alternative: Inline JSON array** (for simple policies):

   ```bash
   oci iam policy create \
     --compartment-id $ROOT_COMP_OCID \
     --name pcy-ds-admin \
     --description "Policy for grp-ds-admin" \
     --statements '[\"Allow group grp-ds-admin to manage data-safe-family in compartment id <datasafe-compartment-ocid>\"]'
   ```

### Step 3: Add Users to Groups

```bash
# Get user OCID
USER_OCID=$(oci iam user list --query "data[?name=='john.doe@example.com'].id | [0]" --raw-output)

# Add to group
oci iam group add-user \
  --user-id $USER_OCID \
  --group-id $(oci iam group list --query "data[?name=='grp-ds-admin'].id | [0]" --raw-output)
```

### Step 4: Verify Policies

```bash
# List policies
oci iam policy list --compartment-id $ROOT_COMP_OCID

# Get policy details
oci iam policy get --policy-id <policy-ocid>

# Test access with specific user
oci data-safe target-database list \
  --compartment-id $DATASAFE_COMP \
  --auth api_key \
  --profile <user-profile>
```

## Testing and Validation

### 1. Service Account Testing

Test automated operations with the service account:

```bash
# Test using API key authentication with service account user profile
# Configure service user profile in ~/.oci/config first

# Test target list
oci data-safe target-database list \
  --compartment-id $DATASAFE_COMP \
  --compartment-id-in-subtree true \
  --profile <service-account-profile>

# Test target update
oci data-safe target-database update \
  --target-database-id <target-ocid> \
  --freeform-tags '{"Environment":"prod"}' \
  --profile <service-account-profile>
```

### 2. Operations Testing

Test with grp-ds-operation user:

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

Test with grp-ds-auditor user:

```bash
# Should succeed: Read targets
oci data-safe target-database list --compartment-id $DATASAFE_COMP

# Should succeed: Read audit trails
oci data-safe audit-trail list --compartment-id $DATASAFE_COMP

# Should fail: Update target
oci data-safe target-database update --target-database-id <target-ocid> --freeform-tags '{}'
# Expected: Authorization failed
```

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
oci iam policy list --compartment-id $ROOT_COMP_OCID | jq '.data[].statements[]'

# Validate dynamic group membership
oci iam dynamic-group get --dynamic-group-id <dynamic-group-ocid>

# Test specific permission
oci data-safe target-database list --compartment-id $DATASAFE_COMP --debug
```

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

## References

- [OCI IAM Policies](https://docs.oracle.com/en-iaas/Content/Identity/Concepts/policies.htm)
- [OCI Data Safe Policies](https://docs.oracle.com/en-iaas/data-safe/doc/iam-policies.html)
- [OCI Dynamic Groups](https://docs.oracle.com/en-iaas/Content/Identity/Tasks/managingdynamicgroups.htm)
- [OCI Policy Reference](https://docs.oracle.com/en-iaas/Content/Identity/policyreference/policyreference.htm)
- [odb_datasafe Documentation](../README.md)

---

## Removing Policies and Groups

### Remove Individual Policy

To remove a specific policy:

```bash
# Set root compartment OCID
export ROOT_COMP_OCID="ocid1.tenancy.oc1..aaaaaaaa..."

# List policies to find the policy ID
oci iam policy list --compartment-id $ROOT_COMP_OCID --all

# Delete specific policy
oci iam policy delete \
  --policy-id <policy-ocid> \
  --force

# Or delete by name
oci iam policy delete \
  --policy-id $(oci iam policy list --compartment-id $ROOT_COMP_OCID --all | jq -r '.data[] | select(.name=="pcy-ds-admin") | .id') \
  --force
```

### Remove All Data Safe Policies

To remove all Data Safe policies at once:

```bash
# Set root compartment OCID
export ROOT_COMP_OCID="ocid1.tenancy.oc1..aaaaaaaa..."

# Delete all Data Safe policies
for policy in pcy-ds-admin pcy-ds-operation pcy-ds-auditor pcy-ds-service; do
  echo "Deleting policy: $policy"
  POLICY_ID=$(oci iam policy list --compartment-id $ROOT_COMP_OCID --all | jq -r ".data[] | select(.name==\"$policy\") | .id")
  if [ -n "$POLICY_ID" ]; then
    oci iam policy delete --policy-id $POLICY_ID --force
    echo "Deleted: $policy"
  else
    echo "Not found: $policy"
  fi
done
```

### Remove Groups

**WARNING:** Only remove groups after ensuring no users are assigned and no policies reference them.

```bash
# List users in a group
oci iam group list-users --group-id <group-ocid>

# Remove all users from group
for user_id in $(oci iam group list-users --group-id <group-ocid> | jq -r '.data[].id'); do
  oci iam group remove-user --group-id <group-ocid> --user-id $user_id
done

# Delete the group
oci iam group delete --group-id <group-ocid> --force

# Or delete by name
oci iam group delete \
  --group-id $(oci iam group list --all | jq -r '.data[] | select(.name=="grp-ds-admin") | .id') \
  --force
```

### Remove All Data Safe Groups

To remove all Data Safe groups:

```bash
# Delete all Data Safe groups
for group in grp-ds-admin grp-ds-operation grp-ds-auditor grp-ds-service; do
  echo "Processing group: $group"
  GROUP_ID=$(oci iam group list --all | jq -r ".data[] | select(.name==\"$group\") | .id")
  
  if [ -n "$GROUP_ID" ]; then
    # Remove all users from group first
    echo "Removing users from $group..."
    for user_id in $(oci iam group list-users --group-id $GROUP_ID | jq -r '.data[].id'); do
      oci iam group remove-user --group-id $GROUP_ID --user-id $user_id
      echo "Removed user: $user_id"
    done
    
    # Delete the group
    oci iam group delete --group-id $GROUP_ID --force
    echo "Deleted group: $group"
  else
    echo "Group not found: $group"
  fi
done
```

### Complete Cleanup Script

Complete script to remove all Data Safe IAM resources:

```bash
#!/bin/bash
# cleanup_datasafe_iam.sh
# Remove all Data Safe policies and groups

# Set root compartment OCID (tenancy OCID)
export ROOT_COMP_OCID="${ROOT_COMP_OCID:-ocid1.tenancy.oc1..aaaaaaaa...}"

echo "=== Data Safe IAM Cleanup ==="
echo "Root Compartment: $ROOT_COMP_OCID"
echo ""

# Step 1: Delete Policies
echo "Step 1: Deleting policies..."
for policy in pcy-ds-admin pcy-ds-operation pcy-ds-auditor pcy-ds-service; do
  POLICY_ID=$(oci iam policy list --compartment-id $ROOT_COMP_OCID --all | jq -r ".data[] | select(.name==\"$policy\") | .id")
  if [ -n "$POLICY_ID" ]; then
    oci iam policy delete --policy-id $POLICY_ID --force
    echo "✓ Deleted policy: $policy"
  fi
done

echo ""
echo "Step 2: Deleting groups..."
# Step 2: Delete Groups (after removing users)
for group in grp-ds-admin grp-ds-operation grp-ds-auditor grp-ds-service; do
  GROUP_ID=$(oci iam group list --all | jq -r ".data[] | select(.name==\"$group\") | .id")
  
  if [ -n "$GROUP_ID" ]; then
    # Remove users
    for user_id in $(oci iam group list-users --group-id $GROUP_ID | jq -r '.data[].id'); do
      oci iam group remove-user --group-id $GROUP_ID --user-id $user_id
    done
    
    # Delete group
    oci iam group delete --group-id $GROUP_ID --force
    echo "✓ Deleted group: $group"
  fi
done

echo ""
echo "=== Cleanup Complete ==="
```

---

## Change Log

| Date       | Version | Author        | Changes                                |
|------------|---------|---------------|----------------------------------------|
| 2026-01-13 | 1.0.0   | Stefan Oehrli | Initial policy document for production |
| 2026-01-14 | 1.0.1   | Stefan Oehrli | Fixed resource types, added removal section |

## Contact

For questions or policy change requests, contact:

- **Data Safe Admin Team:** <datasafe-admins@example.com>
- **Security Team:** <security@example.com>
- **Cloud Operations:** <cloudops@example.com>
