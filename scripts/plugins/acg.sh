#!/usr/bin/env bash
# scripts/plugins/acg.sh — ACG AWS sandbox lifecycle management
#
# Functions: acg_get_credentials acg_provision acg_status acg_extend acg_watch acg_teardown
# Credential parsing: aws_import_credentials (scripts/plugins/aws.sh)

if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/aws.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/antigravity.sh"

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
_ACG_SANDBOX_URL="https://app.pluralsight.com/cloud-playground/cloud-sandboxes"
_ACG_SANDBOX_LIST_URL="${ACG_SANDBOX_LIST_URL:-https://app.pluralsight.com/hands-on/playground/cloud-sandboxes}"
_ACG_WATCH_PID_FILE="${HOME}/.local/share/k3d-manager/acg-watch.pid"
_ACG_CF_STACK_NAME="k3d-manager-cluster"

_acg_check_credentials() {
  _info "[acg] Checking AWS credentials..."
  local arn
  if ! arn=$(_run_command --soft -- aws sts get-caller-identity --region "${ACG_REGION}" --query 'Arn' --output text 2>/dev/null); then
    printf 'ERROR: %s\n' "[acg] AWS credentials invalid or expired. Update ~/.aws/credentials from the ACG console." >&2
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
    pattern = rf"(^Host {host}\$.*?^\\s+HostName\\s+)\\S+"
    content = re.sub(pattern, rf"\\g<1>${new_ip}", content, flags=re.MULTILINE | re.DOTALL)
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

# Deprecated helper — use _aws_write_credentials instead
_acg_write_credentials() {
  _aws_write_credentials "$@"
}

# Deprecated alias — use aws_import_credentials instead
function acg_import_credentials() {
  aws_import_credentials "$@"
}

function acg_get_credentials() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<HELP
Usage: acg_get_credentials [sandbox-url]

Extract AWS credentials from the Pluralsight Cloud Sandbox "Cloud Access" panel
via Chrome CDP (Playwright) and write to ~/.aws/credentials.

Requires Chrome running with --remote-debugging-port=9222. If Chrome is not
already running, it will be launched automatically.

Falls back to: pbpaste | acg_import_credentials

Arguments:
  sandbox-url   (optional) URL of a running sandbox, e.g.
                https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/<id>
                Defaults to ACG_SANDBOX_LIST_URL (listing page — auto-start flow)
HELP
    return 0
  fi

  local sandbox_url="${1:-${_ACG_SANDBOX_LIST_URL}}"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local playwright_script="${script_dir}/../playwright/acg_credentials.js"

  if ! command -v node >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "[acg] node is required for Playwright automation — install Node.js" >&2
    return 1
  fi
  if ! node -e "require('playwright')" 2>/dev/null; then
    printf 'ERROR: %s\n' "[acg] playwright npm module not found — run: cd scripts/playwright && npm install" >&2
    return 1
  fi

  if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    _info "[acg] Chrome CDP not available on port 9222 — launching Chrome..."
    _antigravity_launch
    _antigravity_browser_ready 30
  fi

  _info "[acg] Extracting AWS credentials from ${sandbox_url}..."

  local output
  output=$(node "$playwright_script" "$sandbox_url" 2>&1)

  local access_key secret_key session_token
  access_key=$(printf '%s' "$output" | perl -ne 'if (/AWS_ACCESS_KEY_ID=(\S+)/) {print $1; exit}')
  secret_key=$(printf '%s' "$output" | perl -ne 'if (/AWS_SECRET_ACCESS_KEY=(\S+)/) {print $1; exit}')
  session_token=$(printf '%s' "$output" | perl -ne 'if (/AWS_SESSION_TOKEN=(\S+)/) {print $1; exit}')

  if [[ -z "$access_key" || -z "$secret_key" ]]; then
    _info "[acg] Playwright extraction failed — falling back to stdin paste"
    _info "[acg] Copy the credentials block from the Pluralsight sandbox page, then run:"
    _info "[acg]   pbpaste | ./scripts/k3d-manager acg_import_credentials"
    return 1
  fi

  _aws_write_credentials "$access_key" "$secret_key" "$session_token"
}

function acg_provision() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_provision --confirm [--recreate]

Provision an ACG AWS sandbox EC2 instance. If an instance tagged
'k3d-manager-ubuntu' already exists, start it (if stopped) and update
~/.ssh/config. If no instance exists, provision VPC + subnet + IGW + SG +
key pair + t3.medium EC2.

Flags:
  --confirm    Required — prevents accidental provisioning
  --recreate   Tear down any existing instance before provisioning fresh.
               Use when sandbox state is unknown or TTL has expired.

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

function acg_extend() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_extend

Open the ACG Cloud Sandboxes page to extend the sandbox TTL (+4h).
On macOS, opens the URL in the default browser. On Linux, prints the URL.
HELP
    return 0
  fi

  _info "[acg] Opening ACG sandbox page to extend TTL..."
  _info "[acg] URL: ${_ACG_SANDBOX_URL}"
  if [[ "$(uname)" == "Darwin" ]]; then
    _run_command -- open "${_ACG_SANDBOX_URL}"
    _info "[acg] Click 'Extend Lab' on the sandbox page (+4h)"
  else
    _info "[acg] Open this URL in your browser and click 'Extend Lab':"
    _info "[acg] ${_ACG_SANDBOX_URL}"
  fi
}

function acg_watch() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_watch [interval_seconds]

Background sandbox TTL watcher. Extends the ACG sandbox every 3.5 hours
while the EC2 instance is alive. Stops automatically when the instance
is gone (after acg_teardown).

Requires antigravity_acg_extend to be defined (antigravity.sh sourced).
Default interval: 12600 seconds (3.5 hours).

Example (run after deploy_cluster):
  acg_watch &
  echo "Watcher PID: $!"
HELP
    return 0
  fi

  local interval="${1:-12600}"
  _info "[acg] Sandbox watcher started (PID $$, extending every $((interval / 3600))h)"

  while true; do
    sleep "$interval"
    if [[ -z "$(_acg_get_instance_id 2>/dev/null)" ]]; then
      _info "[acg] Instance gone — watcher stopping."
      return 0
    fi
    _info "[acg] Extending sandbox TTL..."
    if declare -f antigravity_acg_extend > /dev/null 2>&1; then
      antigravity_acg_extend "${_ACG_SANDBOX_URL}" \
        || _info "[acg] Extend failed — open ${_ACG_SANDBOX_URL} to extend manually"
    else
      _info "[acg] antigravity_acg_extend not available — open ${_ACG_SANDBOX_URL} to extend manually"
    fi
  done
}

function acg_teardown() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: acg_teardown [--confirm]

Terminate the ACG sandbox EC2 instance and remove the ubuntu-k3s context
from ~/.kube/config. Does not delete VPC/SG/key pair (those persist across
ACG sessions and are reused by acg_provision).

Requires --confirm to prevent accidental teardown.
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[acg] acg_teardown requires --confirm to prevent accidental teardown" >&2
    return 1
  fi

  _acg_check_credentials || return 1

  local stack_status
  stack_status=$(_run_command --soft -- aws cloudformation describe-stacks \
    --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)

  if [[ -z "$stack_status" || "$stack_status" == "None" ]]; then
    _info "[acg] No CloudFormation stack found — nothing to tear down"
  else
    _info "[acg] Deleting CloudFormation stack ${_ACG_CF_STACK_NAME}..."
    _run_command -- aws cloudformation delete-stack \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"
    _run_command -- aws cloudformation wait stack-delete-complete \
      --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}"
    _info "[acg] Stack deleted"
  fi

  _info "[acg] Removing ubuntu-k3s context from kubeconfig..."
  if kubectl config get-contexts ubuntu-k3s >/dev/null 2>&1; then
    _run_command -- kubectl config delete-context ubuntu-k3s >/dev/null 2>&1 || true
    _info "[acg] Context ubuntu-k3s removed"
  fi

  _info "[acg] Teardown complete"
}
