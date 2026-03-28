#!/usr/bin/env bash
# scripts/plugins/acg.sh — ACG AWS sandbox lifecycle management
#
# Functions: acg_provision acg_status acg_extend acg_teardown

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

_acg_find_vpc() {
  local vpc_id
  vpc_id=$(_run_command --soft -- aws ec2 describe-vpcs --region "${ACG_REGION}" \
    --filters "Name=tag:Name,Values=k3d-manager-vpc" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
  if [[ "$vpc_id" == "None" || "$vpc_id" == "null" ]]; then vpc_id=""; fi
  printf '%s' "$vpc_id"
}

_acg_find_sg() {
  local sg_id
  sg_id=$(_run_command --soft -- aws ec2 describe-security-groups --region "${ACG_REGION}" \
    --filters "Name=group-name,Values=k3d-manager-sg" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
  if [[ "$sg_id" == "None" || "$sg_id" == "null" ]]; then sg_id=""; fi
  printf '%s' "$sg_id"
}

_acg_provision_stack() {
  _info "[acg] Provisioning VPC stack in ${ACG_REGION}..."
  local vpc_id subnet_id igw_id rt_id sg_id ami_id instance_id public_ip

  vpc_id=$(_acg_find_vpc)
  if [[ -n "$vpc_id" ]]; then
    _info "[acg] Reusing existing VPC: $vpc_id"
    subnet_id=$(_run_command --soft -- aws ec2 describe-subnets --region "${ACG_REGION}" \
      --filters "Name=tag:Name,Values=k3d-manager-subnet" \
      --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)
    [[ "$subnet_id" == "None" || "$subnet_id" == "null" ]] && subnet_id=""
  else
    vpc_id=$(_run_command -- aws ec2 create-vpc --region "${ACG_REGION}" --cidr-block "${_ACG_VPC_CIDR}" \
      --query 'Vpc.VpcId' --output text)
    _run_command -- aws ec2 modify-vpc-attribute --region "${ACG_REGION}" --vpc-id "$vpc_id" --enable-dns-hostnames
    _run_command -- aws ec2 create-tags --region "${ACG_REGION}" --resources "$vpc_id" \
      --tags Key=Name,Value=k3d-manager-vpc
    _info "[acg] VPC: $vpc_id"

    subnet_id=$(_run_command -- aws ec2 create-subnet --region "${ACG_REGION}" --vpc-id "$vpc_id" \
      --cidr-block "${_ACG_SUBNET_CIDR}" --availability-zone "${ACG_REGION}a" \
      --query 'Subnet.SubnetId' --output text)
    _run_command -- aws ec2 modify-subnet-attribute --region "${ACG_REGION}" --subnet-id "$subnet_id" --map-public-ip-on-launch
    _run_command -- aws ec2 create-tags --region "${ACG_REGION}" --resources "$subnet_id" \
      --tags Key=Name,Value=k3d-manager-subnet
    _info "[acg] Subnet: $subnet_id"

    igw_id=$(_run_command -- aws ec2 create-internet-gateway --region "${ACG_REGION}" \
      --query 'InternetGateway.InternetGatewayId' --output text)
    _run_command -- aws ec2 attach-internet-gateway --region "${ACG_REGION}" --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
    _info "[acg] Internet gateway: $igw_id"

    rt_id=$(_run_command -- aws ec2 create-route-table --region "${ACG_REGION}" --vpc-id "$vpc_id" \
      --query 'RouteTable.RouteTableId' --output text)
    _run_command -- aws ec2 create-route --region "${ACG_REGION}" --route-table-id "$rt_id" \
      --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id"
    _run_command -- aws ec2 associate-route-table --region "${ACG_REGION}" --route-table-id "$rt_id" --subnet-id "$subnet_id"
    _info "[acg] Route table: $rt_id"
  fi

  sg_id=$(_acg_find_sg)
  if [[ -n "$sg_id" ]]; then
    _info "[acg] Reusing existing security group: $sg_id"
  else
    if [[ "${ACG_ALLOWED_CIDR}" == "0.0.0.0/0" ]]; then
      _info "[acg] NOTE: SSH/API ports open to 0.0.0.0/0 — set ACG_ALLOWED_CIDR=<your-ip>/32 to restrict access"
    fi
    sg_id=$(_run_command -- aws ec2 create-security-group --region "${ACG_REGION}" \
      --group-name k3d-manager-sg --description "k3d-manager EC2" --vpc-id "$vpc_id" \
      --query 'GroupId' --output text)
    _run_command -- aws ec2 authorize-security-group-ingress --region "${ACG_REGION}" --group-id "$sg_id" \
      --protocol tcp --port 22 --cidr "${ACG_ALLOWED_CIDR}"
    _run_command -- aws ec2 authorize-security-group-ingress --region "${ACG_REGION}" --group-id "$sg_id" \
      --protocol tcp --port 6443 --cidr "${ACG_ALLOWED_CIDR}"
    _run_command -- aws ec2 authorize-security-group-ingress --region "${ACG_REGION}" --group-id "$sg_id" \
      --protocol -1 --port -1 --cidr 10.0.0.0/8
    _info "[acg] Security group: $sg_id"
  fi

  if [[ ! -f "${_ACG_KEY_PEM%.pem}.pub" ]]; then
    _info "[acg] Deriving public key from ${_ACG_KEY_PEM}"
    _run_command -- ssh-keygen -y -f "${_ACG_KEY_PEM}" > "${_ACG_KEY_PEM%.pem}.pub"
  fi
  _run_command -- aws ec2 import-key-pair --region "${ACG_REGION}" --key-name "${_ACG_KEY_NAME}" \
    --public-key-material "fileb://${_ACG_KEY_PEM%.pem}.pub" >/dev/null 2>&1 || true

  ami_id=$(_run_command -- aws ec2 describe-images --region "${ACG_REGION}" --owners "${_ACG_AMI_OWNER}" \
    --filters "Name=name,Values=${_ACG_AMI_FILTER}" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
  _info "[acg] AMI: $ami_id"

  instance_id=$(_run_command -- aws ec2 run-instances --region "${ACG_REGION}" \
    --image-id "$ami_id" --instance-type "${_ACG_INSTANCE_TYPE}" \
    --key-name "${_ACG_KEY_NAME}" --subnet-id "$subnet_id" --security-group-ids "$sg_id" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${_ACG_INSTANCE_NAME}}]" \
    --query 'Instances[0].InstanceId' --output text)
  _info "[acg] Instance launched: $instance_id"

  _run_command -- aws ec2 wait instance-running --region "${ACG_REGION}" --instance-ids "$instance_id"
  public_ip=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].PublicIpAddress')
  _acg_update_ssh_config "$public_ip"
  _info "[acg] Instance: $instance_id"
  _info "[acg] Public IP: $public_ip"
  _info "[acg] SSH: ssh ubuntu@${public_ip}"
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
Usage: acg_provision [--confirm]

Provision an ACG AWS sandbox EC2 instance. If an instance tagged
'k3d-manager-ubuntu' already exists, start it (if stopped) and update
~/.ssh/config. If no instance exists, provision VPC + subnet + IGW + SG +
key pair + t3.medium EC2.

Requires --confirm to prevent accidental provisioning.

Config (env overrides):
  ACG_REGION   AWS region (default: us-west-2)

Requirements:
  - aws CLI configured (~/.aws/credentials with ACG sandbox creds)
  - ~/.ssh/k3d-manager-key.pem  (private key for EC2 access)
  - SSH config entries: Host ubuntu, Host ubuntu-tunnel
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[acg] acg_provision requires --confirm to prevent accidental provisioning" >&2
    return 1
  fi

  _acg_check_credentials || return 1
  local instance_id
  instance_id=$(_acg_get_instance_id)

  if [[ -z "$instance_id" ]]; then
    _info "[acg] No instance found — provisioning..."
    _acg_provision_stack
    return 0
  fi

  local state public_ip
  state=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].State.Name')
  public_ip=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].PublicIpAddress')

  if [[ "$state" == "stopped" ]]; then
    _info "[acg] Instance ${instance_id} is stopped — starting"
    _run_command -- aws ec2 start-instances --region "${ACG_REGION}" --instance-ids "$instance_id" >/dev/null
    _run_command -- aws ec2 wait instance-running --region "${ACG_REGION}" --instance-ids "$instance_id"
    public_ip=$(_acg_get_instance_attr "$instance_id" 'Reservations[0].Instances[0].PublicIpAddress')
  fi

  _acg_update_ssh_config "$public_ip"
  _info "[acg] Instance ${instance_id} is ${state} at ${public_ip}"
  _acg_check_k3s
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
  local instance_id
  instance_id=$(_acg_get_instance_id)
  if [[ -z "$instance_id" ]]; then
    _info "[acg] No instance found — nothing to tear down"
    return 0
  fi

  _info "[acg] Terminating instance ${instance_id}..."
  _run_command -- aws ec2 terminate-instances --region "${ACG_REGION}" --instance-ids "$instance_id" >/dev/null

  _info "[acg] Removing ubuntu-k3s context from kubeconfig..."
  if kubectl config get-contexts ubuntu-k3s >/dev/null 2>&1; then
    _run_command -- kubectl config delete-context ubuntu-k3s >/dev/null 2>&1 || true
    _info "[acg] Context ubuntu-k3s removed"
  fi

  _info "[acg] Teardown complete"
}
