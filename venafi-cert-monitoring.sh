#!/bin/bash
# venafi-cert-monitor.sh - Monitor certificate expiry and automate updates
# for certificates stored by the Venafi PKI Secrets Engine in Vault

set -e

# Display help information
function show_help {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Monitors certificates in Vault stored by the Venafi PKI plugin and alerts on upcoming expiry."
    echo
    echo "Options:"
    echo "  -p, --path STRING      Path prefix in Vault (default: venafi-pki)"
    echo "  -w, --warning DAYS     Days before expiry to generate warning (default: 30)"
    echo "  -c, --critical DAYS    Days before expiry to generate critical alert (default: 7)"
    echo "  -u, --update-script    Path to the update script (if automatic updates enabled)"
    echo "  -a, --auto-update      Enable automatic updates using provided certificates"
    echo "  -d, --cert-dir DIR     Directory with new certificates (for auto-update)"
    echo "  -e, --email ADDRESS    Email to send alerts to (comma separated for multiple)"
    echo "  -s, --slack-webhook    Slack webhook URL for notifications"
    echo "  -n, --dry-run          Show what would be done without making changes"
    echo "  -h, --help             Display this help message"
    echo
    echo "Environment variables:"
    echo "  VAULT_ADDR             Vault server address (required)"
    echo "  VAULT_TOKEN            Vault authentication token (required)"
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

# Function to list all certificates in Vault managed by the plugin
function list_certificates {
    local path_prefix="$1"
    
    echo "Listing certificates at path: $path_prefix"
    
    # Use Vault's list API to get all certificates
    local result=$(curl -s \
         -H "X-Vault-Token: $VAULT_TOKEN" \
         -X LIST \
         "$VAULT_ADDR/v1/sys/raw/certs/" | jq -r '.data.keys[]')
    
    echo "$result"
}

# Function to check certificate expiry
function check_certificate_expiry {
    local cert_uid="$1"
    local warning_days="$2"
    local critical_days="$3"
    
    echo "Checking expiry for certificate: $cert_uid"
    
    # Get certificate data from Vault
    local cert_data=$(curl -s \
         -H "X-Vault-Token: $VAULT_TOKEN" \
         -X GET \
         "$VAULT_ADDR/v1/sys/raw/certs/$cert_uid" | jq -r '.data.value.certificate')
    
    if [ -z "$cert_data" ] || [ "$cert_data" = "null" ]; then
        echo "Error: Failed to retrieve certificate data for $cert_uid"
        return 1
    fi
    
    # Save certificate to temporary file
    local temp_cert_file=$(mktemp)
    echo "$cert_data" > "$temp_cert_file"
    
    # Get expiry date
    local expiry_date=$(openssl x509 -in "$temp_cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch=$(date +%s)
    
    # Calculate days until expiry
    local seconds_until_expiry=$((expiry_epoch - now_epoch))
    local days_until_expiry=$((seconds_until_expiry / 86400))
    
    # Get common name
    local common_name=$(openssl x509 -in "$temp_cert_file" -noout -subject | grep -o "CN=[^,/]*" | cut -d= -f2)
    
    # Clean up
    rm "$temp_cert_file"
    
    # Check expiry status
    local status="OK"
    if [ "$days_until_expiry" -le 0 ]; then
        status="EXPIRED"
    elif [ "$days_until_expiry" -le "$critical_days" ]; then
        status="CRITICAL"
    elif [ "$days_until_expiry" -le "$warning_days" ]; then
        status="WARNING"
    fi
    
    echo "$cert_uid,$common_name,$expiry_date,$days_until_expiry,$status"
}

# Function to send email alert
function send_email_alert {
    local cert_uid="$1"
    local common_name="$2"
    local expiry_date="$3"
    local days_until_expiry="$4"
    local status="$5"
    local email="$6"
    
    if [ -z "$email" ]; then
        return
    fi
    
    local subject="Certificate Alert: $status - $common_name expires in $days_until_expiry days"
    local body="Certificate Alert\n\nStatus: $status\nCertificate UID: $cert_uid\nCommon Name: $common_name\nExpiry Date: $expiry_date\nDays Until Expiry: $days_until_expiry"
    
    echo -e "$body" | mail -s "$subject" "$email"
    echo "Email alert sent to $email"
}

# Function to send Slack alert
function send_slack_alert {
    local cert_uid="$1"
    local common_name="$2"
    local expiry_date="$3"
    local days_until_expiry="$4"
    local status="$5"
    local webhook_url="$6"
    
    if [ -z "$webhook_url" ]; then
        return
    fi
    
    local color="good"
    if [ "$status" = "WARNING" ]; then
        color="warning"
    elif [ "$status" = "CRITICAL" ] || [ "$status" = "EXPIRED" ]; then
        color="danger"
    fi
    
    local payload=$(cat <<EOF
{
  "attachments": [
    {
      "fallback": "Certificate Alert: $status - $common_name expires in $days_until_expiry days",
      "color": "$color",
      "title": "Certificate Alert: $status",
      "fields": [
        {
          "title": "Certificate UID",
          "value": "$cert_uid",
          "short": true
        },
        {
          "title": "Common Name",
          "value": "$common_name",
          "short": true
        },
        {
          "title": "Expiry Date",
          "value": "$expiry_date",
          "short": true
        },
        {
          "title": "Days Until Expiry",
          "value": "$days_until_expiry",
          "short": true
        }
      ]
    }
  ]
}
EOF
)
    
    curl -s -X POST -H "Content-type: application/json" --data "$payload" "$webhook_url"
    echo "Slack alert sent"
}

# Function to trigger automatic update
function trigger_update {
    local cert_uid="$1"
    local common_name="$2"
    local update_script="$3"
    local cert_dir="$4"
    local dry_run="$5"
    
    if [ -z "$update_script" ] || [ -z "$cert_dir" ]; then
        echo "Auto-update is enabled but update script or certificate directory is not provided"
        return 1
    fi
    
    if [ ! -f "$update_script" ]; then
        echo "Update script not found: $update_script"
        return 1
    fi
    
    # Check if new certificate files exist
    local cert_file="$cert_dir/$common_name.pem"
    local key_file="$cert_dir/$common_name.key"
    local chain_file="$cert_dir/$common_name.chain.pem"
    
    if [ ! -f "$cert_file" ]; then
        echo "New certificate file not found: $cert_file"
        return 1
    fi
    
    if [ ! -f "$key_file" ]; then
        echo "New private key file not found: $key_file"
        return 1
    fi
    
    # If chain file doesn't exist, that's OK, we'll just update without it
    local chain_param=""
    if [ -f "$chain_file" ]; then
        chain_param="-C $chain_file"
    fi
    
    # Build update command
    local update_cmd="$update_script -c $cert_file -k $key_file $chain_param -i $cert_uid"
    
    if [ "$dry_run" = true ]; then
        echo "DRY RUN: Would execute update command: $update_cmd"
        return
    fi
    
    echo "Executing update command: $update_cmd"
    eval "$update_cmd"
}

# Parse command line arguments
PATH_PREFIX="venafi-pki"
WARNING_DAYS=30
CRITICAL_DAYS=7
UPDATE_SCRIPT=""
AUTO_UPDATE=false
CERT_DIR=""
EMAIL=""
SLACK_WEBHOOK=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p|--path)
            PATH_PREFIX="$2"
            shift 2
            ;;
        -w|--warning)
            WARNING_DAYS="$2"
            shift 2
            ;;
        -c|--critical)
            CRITICAL_DAYS="$2"
            shift 2
            ;;
        -u|--update-script)
            UPDATE_SCRIPT="$2"
            shift 2
            ;;
        -a|--auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        -d|--cert-dir)
            CERT_DIR="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -s|--slack-webhook)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        -n|--dry-run)
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

# If auto-update is enabled, make sure we have all needed parameters
if [ "$AUTO_UPDATE" = true ]; then
    if [ -z "$UPDATE_SCRIPT" ]; then
        echo "Error: Update script is required when auto-update is enabled"
        exit 1
    fi
    
    if [ -z "$CERT_DIR" ]; then
        echo "Error: Certificate directory is required when auto-update is enabled"
        exit 1
    fi
fi

# Get all certificates
echo "Monitoring certificates in Vault with expiry warning at $WARNING_DAYS days and critical at $CRITICAL_DAYS days"
CERTS=$(list_certificates "$PATH_PREFIX")

if [ -z "$CERTS" ]; then
    echo "No certificates found"
    exit 0
fi

# Print header for CSV output
echo "Certificate UID,Common Name,Expiry Date,Days Until Expiry,Status"

# Check each certificate
for cert_uid in $CERTS; do
    result=$(check_certificate_expiry "$cert_uid" "$WARNING_DAYS" "$CRITICAL_DAYS")
    echo "$result"
    
    # Parse the result
    IFS=',' read -r uid common_name expiry_date days_until_expiry status <<< "$result"
    
    # Send alerts if necessary
    if [ "$status" != "OK" ]; then
        send_email_alert "$uid" "$common_name" "$expiry_date" "$days_until_expiry" "$status" "$EMAIL"
        send_slack_alert "$uid" "$common_name" "$expiry_date" "$days_until_expiry" "$status" "$SLACK_WEBHOOK"
        
        # Trigger auto-update if enabled and status is critical or expired
        if [ "$AUTO_UPDATE" = true ] && ([ "$status" = "CRITICAL" ] || [ "$status" = "EXPIRED" ]); then
            trigger_update "$uid" "$common_name" "$UPDATE_SCRIPT" "$CERT_DIR" "$DRY_RUN"
        fi
    fi
done
