# Venafi Certificate Updater - User Guide

## Overview

The `venafi-cert-updater.sh` script allows you to manually update certificates in HashiCorp Vault that were originally managed by the Venafi PKI Secrets Engine. It also provides the ability to view certificate details without modifying them.

## Prerequisites

- Bash shell environment
- `curl` and `jq` installed
- `openssl` for certificate operations
- Access to a HashiCorp Vault instance
- Vault token with appropriate permissions
- Certificate and key files (for update operations)

## Environment Setup

Before using the script, set the following environment variables:

```bash
# Required for all operations
export VAULT_ADDR="https://your-vault-server:8200"
export VAULT_TOKEN="your-vault-token"

# Required only for Vault Enterprise with namespaces
export VAULT_NAMESPACE="your/nested/namespace"  # Optional
```

Make the script executable:

```bash
chmod +x venafi-cert-updater.sh
```

## Basic Usage Examples

### Viewing Certificate Information

To view an existing certificate without modifying it:

```bash
# View by Common Name (CN)
./venafi-cert-updater.sh -i example.com -m cn -s

# View by Serial Number
./venafi-cert-updater.sh -i "00:11:22:33:44" -m serial -s

# View by hash (requires zone and CN or SAN information)
./venafi-cert-updater.sh -z "Default" -n "example.com" -a "www.example.com" -m hash -s
```

### Updating Certificates

To update an existing certificate:

```bash
# Update by Common Name (CN)
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -C chain.pem -i example.com -m cn

# Update by Serial Number
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -i "00:11:22:33:44" -m serial

# Update by hash
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -z "Default" -n "example.com" -a "www.example.com,api.example.com" -m hash
```

### Testing Updates with Dry Run

To see what would happen without making any changes:

```bash
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -i example.com -m cn -d
```

## Command Line Options

| Option | Long Option | Description |
|--------|-------------|-------------|
| `-c` | `--cert FILE` | Certificate file in PEM format (required for update) |
| `-k` | `--key FILE` | Private key file in PEM format (required for update) |
| `-C` | `--chain FILE` | Certificate chain file in PEM format |
| `-i` | `--id STRING` | Certificate UID to update (CN, serial, or hash) |
| `-m` | `--mode STRING` | Storage mode: cn, serial, hash (default: serial) |
| `-z` | `--zone STRING` | Zone (required for hash mode) |
| `-n` | `--cn STRING` | Common name (required for hash mode) |
| `-a` | `--alt-names LIST` | Comma-separated list of SANs (for hash mode) |
| `-p` | `--path STRING` | Path prefix in Vault (default: venafi-pki) |
| `-d` | `--dry-run` | Show what would be done without making changes |
| `-s` | `--show` | Show current certificate content without updating |
| `-h` | `--help` | Display help information |

## Working with Vault Enterprise Namespaces

For Vault Enterprise instances with namespaces, set the `VAULT_NAMESPACE` environment variable:

```bash
# For a top-level namespace
export VAULT_NAMESPACE="namespace1"

# For nested namespaces
export VAULT_NAMESPACE="parent/child/grandchild"
```

The script will automatically:
- Display which namespace is being used
- Include the namespace in all API requests to Vault
- Provide guidance if namespace-related errors occur

## Storage Modes Explained

The script supports three different methods for identifying certificates:

### Common Name (CN) Mode

```bash
./venafi-cert-updater.sh -m cn -i "example.com" -s
```

Uses the certificate's Common Name as the identifier. Simple but may cause conflicts if multiple certificates use the same CN.

### Serial Number Mode (Default)

```bash
./venafi-cert-updater.sh -m serial -i "00:11:22:33:44" -s
```

Uses the certificate's serial number as the identifier. This is the default mode and provides a unique identifier for each certificate.

### Hash Mode

```bash
./venafi-cert-updater.sh -m hash -z "Default" -n "example.com" -a "www.example.com" -s
```

Calculates a SHA1 hash based on the CN, SANs, and zone. This is the most complex but matches the Venafi PKI Secrets Engine's internal storage method.

## Troubleshooting

### Certificate Not Found

If you get an error that the certificate was not found:

1. Verify that you're using the correct mode (`-m`) for the certificate
2. Ensure the certificate UID (`-i`) is correct
3. For Enterprise Vault, check that the namespace is correct
4. Verify that your Vault token has the necessary permissions

### API Errors

If you encounter API errors:

1. Check that `VAULT_ADDR` is correctly set and accessible
2. Verify that `VAULT_TOKEN` is valid and has not expired
3. Ensure `VAULT_NAMESPACE` is correctly formatted (if using Vault Enterprise)
4. Check network connectivity to the Vault server

## Examples for Common Scenarios

### Renewing an Expired Certificate

```bash
# First, find the certificate by displaying it
./venafi-cert-updater.sh -i example.com -m cn -s

# Then update with new certificate files
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -C chain.pem -i example.com -m cn
```

### Working with Multiple Vault Instances

For switching between different Vault instances, you can use environment variables:

```bash
# For Production
export VAULT_ADDR="https://prod-vault:8200"
export VAULT_TOKEN="prod-token"
export VAULT_NAMESPACE="prod"

# For Development
export VAULT_ADDR="https://dev-vault:8200"
export VAULT_TOKEN="dev-token"
export VAULT_NAMESPACE="dev"
```

## Security Considerations

- The script handles sensitive information (private keys and Vault tokens)
- Do not store tokens or keys in script files
- Use environment variables for tokens
- Consider using Vault agent for token management
- Temporary files are created and securely removed during operation
