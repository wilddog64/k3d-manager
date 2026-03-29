#!/usr/bin/env bash
# scripts/plugins/aws.sh — Generic AWS credential helpers
#
# Functions: aws_import_credentials
# Private:   _aws_write_credentials

function _aws_write_credentials() {
  local access_key="$1"
  local secret_key="$2"
  local session_token="${3:-}"
  local creds_file="${HOME}/.aws/credentials"
  mkdir -p "${HOME}/.aws"
  { set +x; } 2>/dev/null
  {
    echo "[default]"
    echo "aws_access_key_id=${access_key}"
    echo "aws_secret_access_key=${secret_key}"
    if [[ -n "${session_token}" ]]; then
      echo "aws_session_token=${session_token}"
    fi
  } > "${creds_file}"
  chmod 600 "${creds_file}"
  _info "[aws] Credentials written to ${creds_file}"
  _info "[aws] Access key: ${access_key:0:4}****"
}

function aws_import_credentials() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: aws_import_credentials < credentials.csv
       pbpaste | aws_import_credentials
       aws_import_credentials < credentials.txt

Read AWS credentials from stdin and write to ~/.aws/credentials.
Supports all standard AWS credential formats:

  # AWS IAM "Download .csv" (new developer onboarding)
  Access key ID,Secret access key
  AKIAIOSFODNN7EXAMPLE,wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

  # Pluralsight Cloud Access panel
  AWS Access Key ID: ASIA...
  AWS Secret Access Key: abc123...
  AWS Session Token: IQo...

  # AWS Console export (unquoted or quoted)
  export AWS_ACCESS_KEY_ID=ASIA...
  export AWS_SECRET_ACCESS_KEY=abc123...
  export AWS_SESSION_TOKEN=IQo...

  # AWS credentials file section
  aws_access_key_id=ASIA...
  aws_secret_access_key=abc123...
  aws_session_token=IQo...
HELP
    return 0
  fi

  _info "[aws] Reading credentials from stdin..."
  local input access_key secret_key session_token
  input=$(cat)

  if printf '%s' "$input" | grep -q '^Access key ID,'; then
    access_key=$(printf '%s' "$input" | awk -F',' 'NR==2 {print $1}')
    secret_key=$(printf '%s' "$input" | awk -F',' 'NR==2 {print $2}')
    session_token=""
  else
    access_key=$(printf '%s' "$input" | perl -ne 's/["\x27]//g; if (/AWS(?:_ACCESS_KEY_ID| Access Key ID)[\s:=]+(\S+)/i) {print $1; exit}')
    secret_key=$(printf '%s' "$input" | perl -ne 's/["\x27]//g; if (/AWS(?:_SECRET_ACCESS_KEY| Secret Access Key)[\s:=]+(\S+)/i) {print $1; exit}')
    session_token=$(printf '%s' "$input" | perl -ne 's/["\x27]//g; if (/AWS(?:_SESSION_TOKEN| Session Token)[\s:=]+(\S+)/i) {print $1; exit}')
  fi

  if [[ -z "$access_key" || -z "$secret_key" ]]; then
    printf 'ERROR: %s\n' "[aws] Could not parse credentials from stdin. Expected access key ID and secret access key." >&2
    return 1
  fi

  _aws_write_credentials "$access_key" "$secret_key" "$session_token"
}
