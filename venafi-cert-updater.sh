#!/bin/bash
# venafi-cert-updater.sh - Contingency script for manually updating certificates in Vault
# that were originally managed by the Venafi PKI Secrets Engine

set -e

# Display help information
function show_help {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Updates certificates stored by the Venafi PKI plugin in HashiCorp Vault."
    echo
    echo "Options:"
    echo "  -c, --cert FILE       Certificate file in PEM format (required)"
    echo "  -k, --key FILE        Private key file in PEM format (required)"
    echo "  -C, --chain FILE      Certificate chain file in PEM format"
    echo "  -i, --id STRING       Certificate UID to update (CN, serial, or hash)"
    echo "  -m, --mode STRING     Storage mode: cn, serial, hash (default: serial)"
    echo "  -z, --zone STRING     Zone (required for hash mode)"
    echo "  -n, --cn STRING       Common name (required for hash mode)"
    echo "  -a, --alt-names LIST  Comma-separated list of SANs (for hash mode)"
    echo "  -p, --path STRING     Path prefix in Vault (default: venafi-pki)"
    echo "  -d, --dry-run         Show what would be done without making changes"
    echo "  -h, --help            Display this help message"
    echo
    echo "Environment variables:"
    echo "  VAULT_ADDR            Vault server address (required)"
    echo "  VAULT_TOKEN           Vault authentication token (required)"
    echo
    echo "Examples:"
    echo "  $0 -c new-cert.pem -k new-key.pem -C chain.pem -i example.com -m cn"
    echo "  $0 -c new-cert.pem -k new-key.pem -i '00:11:22:33:44' -m serial"
    echo
}

# Function to validate that required environment variables are set
function check_env_vars {
    if [ -z "$VAULT_ADDR" ]; then
        echo "Error: VAULT_ADDR environment variable is not set"
        exit 1
    fi
    
    if [ -z "$VAULT_TOKEN" ]; then
        echo "Error: VAULT_TOKEN environment variable is not set"
        exit 1
    fi
}

# Function to calculate hash in the same way the plugin does
function calculate_hash {
    local cn="$1"
    local alt_names="$2"
    local zone="$3"
    
    # Normalize the alt_names (sort and remove duplicates)
    local sorted_alt_names=""
    if [ -n "$alt_names" ]; then
        sorted_alt_names=$(echo "$alt_names" | tr ',' '\n' | sort | uniq | tr '\n' ',' | sed 's/,$//')
    fi
    
    # Create the string to hash
    local string_to_hash=""
    if [ -n "$cn" ]; then
        string_to_hash="${cn};"
    fi
    
    if [ -n "$sorted_alt_names" ]; then
        string_to_hash="${string_to_hash}${sorted_alt_names};"
    fi
    
    string_to_hash="${string_to_hash}${zone}"
    
    # Calculate SHA1 hash
    echo -n "$string_to_hash" | sha1sum | awk '{print $1}'
}

# Function to get the serial number from a certificate
function get_serial_from_cert {
    local cert_file="$1"
    openssl x509 -in "$cert_file" -noout -serial | sed 's/serial=//' | tr 'A-F' 'a-f' | sed 's/../&:/g' | sed 's/:$//'
}

# Function to normalize serial number (replace colons with hyphens)
function normalize_serial {
    echo "$1" | tr ':' '-'
}

# Function to read a certificate file
function read_cert_file {
    local file="$1"
    cat "$file"
}

# Main function to update a certificate in Vault
function update_certificate {
    local cert_content="$1"
    local key_content="$2"
    local chain_content="$3"
    local cert_uid="$4"
    local mode="$5"
    local path_prefix="$6"
    local dry_run="$7"
    
    # Extract serial number from the certificate
    local temp_cert_file=$(mktemp)
    echo "$cert_content" > "$temp_cert_file"
    local serial=$(get_serial_from_cert "$temp_cert_file")
    rm "$temp_cert_file"
    
    # Create JSON payload
    local json_payload=$(cat <<EOF
{
  "certificate": $(echo "$cert_content" | jq -Rs .),
  "certificate_chain": $(echo "$chain_content" | jq -Rs .),
  "private_key": $(echo "$key_content" | jq -Rs .),
  "serial_number": "$(echo "$serial" | tr -d '\n')"
}
EOF
)
    
    # Determine the path based on the mode
    local storage_path="certs/$cert_uid"
    
    # Show what we're about to do
    echo "Updating certificate with UID: $cert_uid"
    echo "Storage mode: $mode"
    echo "Storage path: $storage_path"
    
    if [ "$dry_run" = true ]; then
        echo "DRY RUN: Would update certificate in Vault at path: $storage_path"
        echo "Payload would be:"
        echo "$json_payload" | jq '.'
        return
    fi
    
    # Write to Vault
    local temp_json=$(mktemp)
    echo "$json_payload" > "$temp_json"
    
    # Use raw storage API to write directly
    echo "Writing certificate to Vault storage..."
    curl -s \
         -H "X-Vault-Token: $VAULT_TOKEN" \
         -H "Content-Type: application/json" \
         -X PUT \
         -d "{\"value\": $(echo "$json_payload" | jq -c .)}" \
         "$VAULT_ADDR/v1/sys/raw/$storage_path"
    
    rm "$temp_json"
    
    echo "Certificate updated successfully at path: $storage_path"
}

# Parse command line arguments
CERT_FILE=""
KEY_FILE=""
CHAIN_FILE=""
CERT_UID=""
MODE="serial"
ZONE=""
CN=""
ALT_NAMES=""
PATH_PREFIX="venafi-pki"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--cert)
            CERT_FILE="$2"
            shift 2
            ;;
        -k|--key)
            KEY_FILE="$2"
            shift 2
            ;;
        -C|--chain)
            CHAIN_FILE="$2"
            shift 2
            ;;
        -i|--id)
            CERT_UID="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -n|--cn)
            CN="$2"
            shift 2
            ;;
        -a|--alt-names)
            ALT_NAMES="$2"
            shift 2
            ;;
        -p|--path)
            PATH_PREFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
check_env_vars

if [ -z "$CERT_FILE" ]; then
    echo "Error: Certificate file is required"
    show_help
    exit 1
fi

if [ -z "$KEY_FILE" ]; then
    echo "Error: Private key file is required"
    show_help
    exit 1
fi

# If chain file is not provided, use an empty string
if [ -z "$CHAIN_FILE" ]; then
    CHAIN_CONTENT=""
else
    CHAIN_CONTENT=$(read_cert_file "$CHAIN_FILE")
fi

# Calculate certificate UID if not provided
if [ -z "$CERT_UID" ]; then
    if [ "$MODE" = "cn" ]; then
        if [ -z "$CN" ]; then
            echo "Error: Common name is required when mode is 'cn' and certificate UID is not provided"
            exit 1
        fi
        CERT_UID="$CN"
    elif [ "$MODE" = "serial" ]; then
        CERT_CONTENT=$(read_cert_file "$CERT_FILE")
        temp_cert_file=$(mktemp)
        echo "$CERT_CONTENT" > "$temp_cert_file"
        SERIAL=$(get_serial_from_cert "$temp_cert_file")
        rm "$temp_cert_file"
        CERT_UID=$(normalize_serial "$SERIAL")
    elif [ "$MODE" = "hash" ]; then
        if [ -z "$CN" ] && [ -z "$ALT_NAMES" ]; then
            echo "Error: Either common name or alt names is required when mode is 'hash'"
            exit 1
        fi
        if [ -z "$ZONE" ]; then
            echo "Error: Zone is required when mode is 'hash'"
            exit 1
        fi
        CERT_UID=$(calculate_hash "$CN" "$ALT_NAMES" "$ZONE")
    else
        echo "Error: Invalid mode: $MODE"
        show_help
        exit 1
    fi
    
    echo "Calculated certificate UID: $CERT_UID"
fi

# Read certificate and key files
CERT_CONTENT=$(read_cert_file "$CERT_FILE")
KEY_CONTENT=$(read_cert_file "$KEY_FILE")

# Update the certificate
update_certificate "$CERT_CONTENT" "$KEY_CONTENT" "$CHAIN_CONTENT" "$CERT_UID" "$MODE" "$PATH_PREFIX" "$DRY_RUN"
