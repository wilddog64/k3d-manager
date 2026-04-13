#!/usr/bin/env bash
# scripts/plugins/aws.sh — AWS credential helpers and CloudFormation provisioning
#
# Functions: aws_import_credentials acg_provision acg_status
# Private:   _aws_write_credentials _acg_check_credentials _acg_get_instance_id
#            _acg_get_instance_attr _acg_update_ssh_config _acg_upsert_ssh_host
#            _acg_cf_deploy _acg_check_k3s

: "${ACG_REGION:=us-west-2}"
: "${ACG_ALLOWED_CIDR:=0.0.0.0/0}"
_ACG_INSTANCE_NAME="k3d-manager-ubuntu"
_ACG_INSTANCE_TYPE="t3.medium"
_ACG_KEY_NAME="k3d-manager-key"
_ACG_KEY_PEM="${HOME}/.ssh/k3d-manager-key.pem"
_ACG_SSH_CONFIG="${HOME}/.ssh/config"
_ACG_AMI_OWNER="099720109477"
_ACG_AMI_FILTER="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
_ACG_VPC_CIDR="10.0.0.0/16"
_ACG_SUBNET_CIDR="10.0.1.0/24"
_ACG_CF_STACK_NAME="k3d-manager-cluster"
_ACG_SANDBOX_URL="https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"

function _aws_write_credentials() {
  local access_key="$1"
  local secret_key="$2"
  local session_token="${3:-}"
  local creds_file="${HOME}/.aws/credentials"
  mkdir -p "${HOME}/.aws"

  local creds_content
  creds_content="[default]"$'\n'
  creds_content+="aws_access_key_id=${access_key}"$'\n'
  creds_content+="aws_secret_access_key=${secret_key}"$'\n'
  if [[ -n "${session_token}" ]]; then
    creds_content+="aws_session_token=${session_token}"$'\n'
  fi

  _write_sensitive_file "${creds_file}" "${creds_content}"
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

  if printf '%s' "$input" | head -n1 | grep -q ',' && \
     printf '%s' "$input" | head -n1 | grep -qi 'access key id'; then
    local header key_col secret_col
    header=$(printf '%s' "$input" | head -n1)
    key_col=$(printf '%s' "$header" | awk -F',' '{for(i=1;i<=NF;i++){v=$i; gsub(/^[[:space:]"]+|[[:space:]"]+$/,"",v); if(v=="Access key ID"){print i; exit}}}')
    secret_col=$(printf '%s' "$header" | awk -F',' '{for(i=1;i<=NF;i++){v=$i; gsub(/^[[:space:]"]+|[[:space:]"]+$/,"",v); if(v=="Secret access key"){print i; exit}}}')
    access_key=$(printf '%s' "$input" | awk -F',' -v col="${key_col}" 'NR==2{v=$col; gsub(/^[[:space:]"]+|[[:space:]"]+$/,"",v); print v}')
    secret_key=$(printf '%s' "$input" | awk -F',' -v col="${secret_col}" 'NR==2{v=$col; gsub(/^[[:space:]"]+|[[:space:]"]+$/,"",v); print v}')
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

_acg_check_credentials() {
  _info "[acg] Checking AWS credentials..."
  local arn
  if ! arn=$(_run_command --soft -- aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text 2>/dev/null); then
    printf 'ERROR: %s\n' "[acg] AWS credentials invalid or expired." >&2
    printf 'ERROR: %s\n' "[acg] If the sandbox was removed (expired TTL):" >&2
    printf 'ERROR: %s\n' "[acg]   1. Start a new sandbox at ${_ACG_SANDBOX_URL}" >&2
    printf 'ERROR: %s\n' "[acg]   2. Run: acg_get_credentials" >&2
    printf 'ERROR: %s\n' "[acg]   3. Re-run: make up" >&2
    printf 'ERROR: %s\n' "[acg] If the sandbox is still running: update ~/.aws/credentials from the ACG console." >&2
    return 1
  fi
  _info "[acg] Credentials OK (${arn})"
}

_acg_get_instance_id() {
  local instance_id
  instance_id=$(_run_command --soft -- aws ec2 describe-instances --region "${ACG_REGION}" \
    --filters "Name=tag:Name,Values=${_ACG_INSTANCE_NAME}" \
              "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
  if [[ "$instance_id" == "None" || "$instance_id" == "null" ]]; then
    instance_id=""
  fi
  printf '%s' "$instance_id"
}

_acg_get_instance_attr() {
  local instance_id="$1" query="$2"
  _run_command --soft -- aws ec2 describe-instances --region "${ACG_REGION}" --instance-ids "$instance_id" \
    --query "$query" --output text 2>/dev/null || true
}

_acg_update_ssh_config() {
  local new_ip="$1"
  [[ -f "${_ACG_SSH_CONFIG}" ]] || return 0
  _info "[acg] Updating SSH config with IP ${new_ip}"
  local python_cmd
  python_cmd=$(cat <<PY
import re
path = r"${_ACG_SSH_CONFIG}"
with open(path, 'r') as f:
    content = f.read()
for host in ('ubuntu', 'ubuntu-tunnel'):
    pattern = rf"(^Host {host}\$.*?^\s+HostName\s+)\S+"
    content = re.sub(pattern, rf"\g<1>${new_ip}", content, flags=re.MULTILINE | re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
PY
)
  _run_command -- python3 -c "$python_cmd"
}

_acg_upsert_ssh_host() {
  local alias="$1" ip="$2"
  [[ -f "${_ACG_SSH_CONFIG}" ]] || return 0
  _info "[acg] Updating SSH config: Host ${alias} → ${ip}"
  local python_cmd
  python_cmd=$(cat <<PY
import re
alias = "${alias}"
ip    = "${ip}"
path  = "${_ACG_SSH_CONFIG}"
with open(path, 'r') as f:
    content = f.read()
pattern = r"(^Host " + re.escape(alias) + r"\$.*?^\s+HostName\s+)\S+"
m = re.search(pattern, content, re.MULTILINE | re.DOTALL)
if m:
    content = re.sub(pattern, r"\g<1>" + ip, content, flags=re.MULTILINE | re.DOTALL)
else:
    block = "\nHost ${alias}\n  HostName ${ip}\n  User ubuntu\n  IdentityFile ~/.ssh/k3d-manager-key.pem\n  StrictHostKeyChecking no\n"
    content = content.rstrip("\n") + block
with open(path, 'w') as f:
    f.write(content)
PY
)
  _run_command -- python3 -c "$python_cmd"
}

_acg_cf_deploy() {
  local ami_id
  ami_id=$(_run_command -- aws ec2 describe-images --region "${ACG_REGION}" --owners "${_ACG_AMI_OWNER}" \
    --filters "Name=name,Values=${_ACG_AMI_FILTER}" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
  _info "[acg] AMI: ${ami_id}"

  if [[ ! -f "${_ACG_KEY_PEM%.pem}.pub" ]]; then
    _info "[acg] Deriving public key from ${_ACG_KEY_PEM}"
    _run_command -- ssh-keygen -y -f "${_ACG_KEY_PEM}" > "${_ACG_KEY_PEM%.pem}.pub"
  fi
  _run_command --soft -- aws ec2 import-key-pair --region "${ACG_REGION}" --key-name "${_ACG_KEY_NAME}" \
    --public-key-material "fileb://${_ACG_KEY_PEM%.pem}.pub" >/dev/null 2>&1

  _info "[acg] Deploying CloudFormation stack ${_ACG_CF_STACK_NAME} (3 nodes in parallel)..."
  _run_command -- aws cloudformation deploy \
    --region "${ACG_REGION}" \
    --stack-name "${_ACG_CF_STACK_NAME}" \
    --template-file "${SCRIPT_DIR}/etc/acg-cluster.yaml" \
    --parameter-overrides \
      "KeyName=${_ACG_KEY_NAME}" \
      "AllowedCidr=${ACG_ALLOWED_CIDR}" \
      "InstanceType=${_ACG_INSTANCE_TYPE}" \
      "AmiId=${ami_id}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

  local server_ip agent1_ip agent2_ip
  server_ip=$(_run_command -- aws cloudformation describe-stacks --region "${ACG_REGION}" \
    --stack-name "${_ACG_CF_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey==\`ServerPublicIP\`].OutputValue" --output text)
  agent1_ip=$(_run_command -- aws cloudformation describe-stacks --region "${ACG_REGION}" \
    --stack-name "${_ACG_CF_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey==\`Agent1PublicIP\`].OutputValue" --output text)
  agent2_ip=$(_run_command -- aws cloudformation describe-stacks --region "${ACG_REGION}" \
    --stack-name "${_ACG_CF_STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey==\`Agent2PublicIP\`].OutputValue" --output text)

  _acg_update_ssh_config "${server_ip}"
  _acg_upsert_ssh_host "ubuntu-1" "${agent1_ip}"
  _acg_upsert_ssh_host "ubuntu-2" "${agent2_ip}"

  _info "[acg] Server:  ${server_ip}"
  _info "[acg] Agent 1: ${agent1_ip}"
  _info "[acg] Agent 2: ${agent2_ip}"
  _info "[acg] NOTE: install k3s via ./scripts/k3d-manager deploy_app_cluster --confirm"
}

_acg_check_k3s() {
  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local cmd="su -c 'k3s kubectl get nodes 2>/dev/null' root"
  if _run_command --soft -- ssh -o ConnectTimeout=10 "${ssh_host}" "${cmd}" >/dev/null 2>&1; then
    _info "[acg] k3s is running"
  else
    _info "[acg] WARNING: k3s not responding — run: ./scripts/k3d-manager deploy_app_cluster --confirm"
  fi
}

function acg_provision() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_provision --confirm [--recreate]

Provision a 3-node k3s cluster on ACG AWS sandbox via CloudFormation.
Creates a VPC + subnet + IGW + SG + key pair + 1 server EC2 + 2 agent EC2
instances (t3.medium). Updates ~/.ssh/config with Host entries for
ubuntu (server), ubuntu-1 and ubuntu-2 (agents).

Flags:
  --confirm    Required — prevents accidental provisioning
  --recreate   Tear down any existing CloudFormation stack before
               reprovisioning. Use when sandbox state is unknown or
               TTL has expired.

Config (env overrides):
  ACG_REGION   AWS region (default: us-west-2)

Requirements:
  - aws CLI configured (~/.aws/credentials with ACG sandbox creds)
  - ~/.ssh/k3d-manager-key.pem  (private key for EC2 access)
  - SSH config entries: Host ubuntu, Host ubuntu-tunnel
HELP
    return 0
  fi

  local _confirm=0 _recreate=0
  for _arg in "$@"; do
    case "$_arg" in
      --confirm)  _confirm=1 ;;
      --recreate) _recreate=1 ;;
    esac
  done

  if [[ $_confirm -eq 0 ]]; then
    printf 'ERROR: %s\n' "[acg] acg_provision requires --confirm to prevent accidental provisioning" >&2
    return 1
  fi

  _acg_check_credentials || return 1

  if [[ $_recreate -eq 1 ]]; then
    _info "[acg] --recreate: deleting existing CloudFormation stack before reprovisioning..."
    _run_command --soft -- aws cloudformation delete-stack \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" >/dev/null 2>&1 || true
    _run_command --soft -- aws cloudformation wait stack-delete-complete \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" 2>/dev/null || true
  fi

  _acg_cf_deploy
}

function acg_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_status

Check the state of the ACG AWS sandbox EC2 instance. Reports instance ID,
state, public IP, and whether k3s is responding. Does not provision.
HELP
    return 0
  fi

  _acg_check_credentials || return 1
  local instance_id
  instance_id=$(_acg_get_instance_id)
  if [[ -z "$instance_id" ]]; then
    printf 'ERROR: %s\n' "[acg] No instance found. Run acg_provision --confirm first." >&2
    return 1
  fi

  local state public_ip
  state=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].State.Name')
  public_ip=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].PublicIpAddress')
  _acg_update_ssh_config "$public_ip"
  _info "[acg] Instance ${instance_id} is ${state} at ${public_ip}"
  _acg_check_k3s
}
