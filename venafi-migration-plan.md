# Venafi Plugin Contingency and Migration Plan

This document outlines a comprehensive plan to ensure certificate continuity if the Venafi PKI Secrets Engine for HashiCorp Vault becomes unsupported or non-functional. The plan includes both short-term contingencies and a long-term migration strategy.

## Objectives

1. Ensure uninterrupted certificate access for applications
2. Provide mechanisms to manually update certificates in Vault
3. Monitor certificate expiry to prevent outages
4. Establish a smooth transition path to a new certificate management solution

## Short-Term Contingency Plan

### 1. Certificate Update Mechanism

The `venafi-cert-updater.sh` script provides a method to manually update certificates stored by the Venafi plugin without relying on the plugin itself. This script:

- Takes a new certificate, private key, and chain as inputs
- Correctly formats the data according to the plugin's expected structure
- Writes directly to Vault's storage API
- Supports all storage modes (by CN, serial, or hash)

#### Usage Examples:

```bash
# Update certificate stored by CN
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -C chain.pem -i example.com -m cn

# Update certificate stored by serial number
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -i '00-11-22-33-44' -m serial

# Update certificate stored by hash (requires zone info)
./venafi-cert-updater.sh -c new-cert.pem -k new-key.pem -n example.com \
  -a "www.example.com,api.example.com" -z "DevOps\\Certificates" -m hash
```

### 2. Certificate Monitoring

The `venafi-cert-monitor.sh` script monitors certificates stored in Vault and alerts on upcoming expiry. Features include:

- Configurable warning thresholds (default: 30 days warning, 7 days critical)
- Email and Slack notifications
- Optional automatic certificate updates
- CSV output for integration with other monitoring systems

#### Usage Examples:

```bash
# Basic monitoring with email alerts
./venafi-cert-monitor.sh -e admin@example.com

# Monitoring with Slack alerts and custom thresholds
./venafi-cert-monitor.sh -w 45 -c 14 -s "https://hooks.slack.com/services/xxx/yyy/zzz"

# Monitoring with automatic updates
./venafi-cert-monitor.sh -a -u ./venafi-cert-updater.sh -d /path/to/new/certs \
  -e admin@example.com
```

## Long-Term Migration Strategy

### Phase 1: Preparation (1-2 months)

1. **Inventory current certificates**
   - List all certificates managed by the Venafi plugin
   - Document certificate details (CN, SANs, expiry, applications using them)
   - Classify certificates by criticality and application

2. **Set up monitoring**
   - Implement certificate monitoring using the provided script
   - Configure alerts to appropriate teams
   - Establish renewal procedures

3. **Document certificate access patterns**
   - Identify how applications retrieve certificates from Vault
   - Document API paths and authentication methods
   - Review application code for direct dependencies on the plugin

### Phase 2: Implement Alternative Solution (2-3 months)

1. **Select replacement solution**
   - Options include:
     - HashiCorp Vault's built-in PKI secrets engine
     - Direct integration with a new CA
     - Alternative certificate management platform
     - Self-hosted CA (e.g., CFSSL, step-ca)

2. **Set up parallel infrastructure**
   - Implement chosen solution alongside existing Venafi plugin
   - Configure certificate policies matching current requirements
   - Establish automation for certificate lifecycle

3. **Create compatibility layer (if needed)**
   - Develop an API compatibility layer that mimics Venafi plugin endpoints
   - Map requests to new certificate solution
   - Test with non-production applications

### Phase 3: Migration (3-6 months)

1. **Gradual application migration**
   - Update applications in batches, starting with non-critical systems
   - Configure applications to use new certificate endpoints
   - Maintain backward compatibility during transition

2. **Certificate renewal through new system**
   - As certificates approach expiry, renew through new system instead of Venafi
   - Use the updating script to place new certificates in old paths
   - Gradually shift certificate management responsibility

3. **Validation and verification**
   - Monitor application logs for certificate-related errors
   - Verify certificate validity and parameters
   - Test certificate revocation and renewal processes

### Phase 4: Completion and Cleanup (1 month)

1. **Complete transition**
   - Finalize migration of all applications
   - Verify all certificates are now managed by the new system
   - Document new architecture and procedures

2. **Decommissioning**
   - Once all applications have been migrated:
     - Keep the Venafi plugin paths available (but updated through new system)
     - Consider read-only mode for remaining Venafi paths
     - Plan eventual removal of Venafi plugin

## Implementation Requirements

### Tools and Resources

1. **Scripts**
   - venafi-cert-updater.sh: For manually updating certificates
   - venafi-cert-monitor.sh: For monitoring certificate expiry

2. **Infrastructure**
   - Access to Vault's storage API
   - Certificate management system
   - Monitoring and alerting systems

3. **Skills**
   - HashiCorp Vault administration
   - PKI and certificate management
   - Scripting and automation
   - Application integration

### Risk Mitigation

1. **Testing**
   - Thoroughly test manual update procedures before implementation
   - Verify application behavior with manually updated certificates
   - Create a test environment that mirrors production

2. **Backup**
   - Take regular backups of Vault storage
   - Document and test recovery procedures
   - Maintain copies of all certificates and private keys

3. **Phased Approach**
   - Implement changes gradually to limit impact
   - Start with non-critical applications
   - Maintain ability to revert to previous state

## Conclusion

This contingency and migration plan provides both immediate remediation options if the Venafi plugin becomes unsupported, and a pathway to a fully independent certificate management solution. By implementing this plan, you can ensure continuous certificate availability for applications while transitioning to a new certificate management approach.

The provided scripts enable manual intervention when needed, while the phased migration strategy minimizes disruption to applications and services. Regular monitoring and testing throughout the process will help identify and address issues before they impact production systems.
