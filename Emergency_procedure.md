# Restricted Raw Storage Access Procedure for Hashicorp Vault

## Overview

This document outlines a procedure for safely accessing and modifying specific data in Vault's raw storage (`sys/raw` endpoint), particularly for scenarios where plugin-created data needs modification when normal plugin functionality is unavailable or unsupported.

**Target Use Case:** Modifying values at the `sys/raw/` path within Vault namespaces

## ⚠️ Warning

Manipulating raw storage in Vault is potentially dangerous and can lead to data corruption if performed incorrectly. This procedure should be:
- Used only when absolutely necessary
- Performed during a maintenance window
- Tested in a non-production environment first
- Executed with proper backups in place

## Prerequisites

- Administrative access to Vault server configuration
- Permission to restart the Vault service
- Root or administrative access within Vault

## Procedure

### 1. Create a Restrictive Policy

Create a file named `namespace-pki-raw-restricted.hcl` with the following content:

```hcl
# Allow access only to the specific PKI path in raw storage
# Replace "your-namespace" with your actual namespace name
path "sys/raw/+-pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Explicitly deny all other sys/raw paths
path "sys/raw/*" {
  capabilities = ["deny"]
}

# Deny access to other sys paths
path "sys/*" {
  capabilities = ["deny"]
}

# Allow token self-lookup (for token validation)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

### 2. Apply the Policy in Vault

```bash
# If you're using namespaces, specify the namespace when writing the policy
vault policy write -namespace=your-namespace namespace-pki-raw-restricted namespace-pki-raw-restricted.hcl
```

### 3. Create a Restricted Token with the Policy

```bash
# Create token in the appropriate namespace
vault token create -namespace=your-namespace -policy=namespace-pki-raw-restricted -ttl=1h
```

Save the token value securely. It will look similar to:
```
you dont need an example for that do you ?
```

### 4. Modify Vault's Configuration File

Edit your Vault server configuration file (e.g., `vault.hcl`) and add:

```hcl
enable_raw_endpoint = true
```

### 5. Restart Vault to Apply the Configuration Change

```bash
# If using systemd
sudo systemctl restart vault

# Or using the reload command if supported in your environment
vault operator reload
```

### 6. Perform Raw Storage Operations

Use curl or another HTTP client with your restricted token:

```bash
# For namespaced operations, include the namespace header
curl -H "X-Vault-Token: your-restricted-token" \
     -H "X-Vault-Namespace: your-namespace" \
     -X GET \
     https://your-vault-server:8200/v1/sys/raw/your-namespace-pki/your-specific-path
```

To update values:

```bash
curl -H "X-Vault-Token: your-restricted-token" \
     -H "X-Vault-Namespace: your-namespace" \
     -X PUT \
     -d '{"value": "your-modified-data"}' \
     https://your-vault-server:8200/v1/sys/raw/your-namespace-pki/your-specific-path
```

### 7. Revoke the Token Once Done

```bash
# Revoke the token in the correct namespace
vault token revoke -namespace=your-namespace your-restricted-token
```

### 8. Modify Vault's Configuration File Again

Edit your Vault configuration file and set:

```hcl
enable_raw_endpoint = false
```

### 9. Restart Vault to Disable Raw Access

```bash
sudo systemctl restart vault
# or
vault operator reload
```

## Troubleshooting

### Permission Denied Errors

If you receive permission denied errors despite using the correct token:
- Verify the token is still valid: `vault token lookup -namespace=your-namespace <token>`
- Check that the policy is correctly associated with the token
- Ensure the path you're accessing matches exactly what's allowed in the policy
- Confirm you're using the correct namespace in your API calls with the `X-Vault-Namespace` header

### Raw Endpoint Not Accessible

If the raw endpoint returns 404 errors:
- Confirm that `enable_raw_endpoint = true` is properly set in the configuration
- Verify that Vault was successfully restarted after the configuration change
- Check Vault server logs for any errors during restart
- Ensure you're using the correct namespace path format (e.g., `your-namespace-pki` matches your actual namespace)

## Additional Security Recommendations

1. **Create Backups**: Always back up your Vault data before manipulating raw storage
2. **Document Changes**: Keep detailed logs of what was changed and why
3. **Audit**: Review audit logs before and after the procedure
4. **Time Window**: Schedule this procedure during low-traffic periods
5. **Testing**: Practice this procedure in a test environment first
6. **Namespace Validation**: Double-check namespace paths in both policies and API calls
7. **Path Structure**: Verify the correct raw storage path structure with a read operation before attempting writes

## References

- [Vault HTTP API - /sys/raw Documentation](https://www.vaultproject.io/api-docs/system/raw)
- [Vault Policy Documentation](https://www.vaultproject.io/docs/concepts/policies)
- [Vault Configuration Documentation](https://www.vaultproject.io/docs/configuration)
- [Vault Namespaces Documentation](https://www.vaultproject.io/docs/enterprise/namespaces)

## Revision History

- **v1.0** - Initial procedure documentation
