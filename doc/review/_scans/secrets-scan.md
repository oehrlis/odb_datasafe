# Secrets Scan Report

**Scan Date:** 2026-06-28  
**Scope:** Full repository (excluding `.git/`, `dist/`, `log/`, `doc/release_notes/archive/`)  
**Tool:** Manual ripgrep patterns + file inspection

---

## Findings Summary

| Pattern Category | Count | Status |
|---|---|---|
| Hardcoded Passwords | 1 | **FOUND** |
| OCI OCIDs | 0 | Clear |
| Private IP Addresses | 0 | Clear |
| AWS/OCI API Keys | 0 | Clear |
| SSH Private Key Material | 0 | Clear |
| Base64-encoded Secrets | 0 | Clear |
| Wallet Password Patterns | 0 | Clear |

---

## Detailed Findings

### 1. Hardcoded Password in SQL Script

**File:** `sql/create_ds_admin_user.sql`  
**Line:** 40  
**Pattern:** `password=value` (hardcoded default)  
**Match:**

```
DEFINE _ds_passwd  = 'DS_Admin.2025'
```

**Context:** Default parameter value used in SQL script for creating Data Safe admin user. This is a **placeholder/example password**, not a real production credential. The script accepts parameters and allows override via arguments. However, the hardcoded default should be removed or replaced with a prompt-based mechanism.

**Risk Level:** Low-Medium (example value only, but discourages secure practices in template scripts)

---

## OCI Resource Identifiers (Non-sensitive Examples)

The following are **placeholder OCID patterns** used in example configs and documentation — these are NOT real credentials:

| File | Line | Type | Value |
|---|---|---|---|
| `etc/datasafe.conf.example` | 30 | Example OCID | `ocid1.compartment.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 31 | Example OCID | `ocid1.compartment.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 35 | Example OCID | `ocid1.compartment.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 36 | Example OCID | `ocid1.compartment.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 87 | Example OCID | `ocid1.datasafeonpremconnector.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 91 | Example OCID | `ocid1.compartment.oc1..aaaa...` |
| `etc/datasafe.conf.example` | 94 | Example OCID | `ocid1.datasafeonpremconnector.oc1..aaaa...` |
| `tests/integration_tests.bats` | 26 | Mock OCID | `ocid1.compartment.oc1..integration-test` |

**Status:** These are all template/example placeholders with `..aaaa...` or `..integration-test` suffixes, not real credentials.

---

## Secrets Handling Best Practices Found

**Positive:** The codebase demonstrates secure patterns:

1. **1Password Integration** — Scripts reference `op read "op://vault/item/field"` for credential retrieval (documented in CLAUDE.md)
2. **No Hardcoded OCI Credentials** — All OCI auth delegated to OCI CLI (`~/.oci/config` via profile)
3. **Credential File Support** — Accepts external JSON credential files rather than command-line secrets
4. **Environment Variable Isolation** — Credentials handled through `DS_USER` / `DS_SECRET` variables, not embedded in code
5. **Prompt-based Input** — Scripts prompt for missing credentials interactively when needed

---

## Recommendations

1. **Remove default password from SQL template:**  
   Line 40 in `sql/create_ds_admin_user.sql`: Replace `'DS_Admin.2025'` with empty string or add a comment requiring user override.

2. **Document credential handling:**  
   Add security note to README or documentation clarifying that credentials are never committed to source control.

3. **Test coverage:**  
   Ensure test mocks never include real credentials (verified: all test fixtures use mock OCIDs).

---

## Files Reviewed

- Configuration: `etc/datasafe.conf.example`, `etc/odb_datasafe.conf.example`, `etc/env.sh`
- Scripts: 40+ bin scripts, 3 library modules
- Tests: 20+ BATS test files
- SQL: `sql/create_ds_admin_user.sql`, `sql/create_ds_admin_prerequisites.sql`
- CI/CD: `.github/workflows/ci.yml`
- JSON Policies: `etc/pcy-*.json.example`

---

## Conclusion

**Overall Risk: LOW**

The repository follows secure practices for credential handling. The single finding (hardcoded SQL password) is a template default with low risk but should be addressed per recommendations above.

No real credentials, API keys, OCIDs, or sensitive infrastructure data were discovered in the repository.
