#!/usr/bin/env bash
# bin/acg-sandbox.sh — Verify or provision the ACG AWS sandbox EC2 instance
#
# Usage:
#   ./bin/acg-sandbox.sh           # check instance; provision if missing
#   ./bin/acg-sandbox.sh check     # check only, no provisioning
#   ./bin/acg-sandbox.sh provision # force provision (skip check)
#
# Requirements:
#   - aws CLI configured (~/.aws/credentials with ACG sandbox creds)
#   - ~/.ssh/k3d-manager-key.pem  (private key for EC2 access)
#   - SSH config entries: Host ubuntu, Host ubuntu-tunnel

set -euo pipefail

REGION="${ACG_REGION:-us-west-2}"
INSTANCE_NAME="k3d-manager-ubuntu"
INSTANCE_TYPE="t3.large"
KEY_NAME="k3d-manager-key"
KEY_PEM="$HOME/.ssh/k3d-manager-key.pem"
SSH_CONFIG="$HOME/.ssh/config"
AMI_OWNER="099720109477"
AMI_FILTER="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"

_info()  { echo "[acg-sandbox] $*"; }
_error() { echo "[acg-sandbox] ERROR: $*" >&2; exit 1; }

# --- Step 1: verify AWS CLI credentials ---
_check_credentials() {
  _info "Checking AWS credentials..."
  if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    _error "AWS CLI credentials invalid or expired. Update ~/.aws/credentials from the ACG console."
  fi
  _info "Credentials OK ($(aws sts get-caller-identity --region "$REGION" --query 'Arn' --output text))"
}

# --- Step 2: check if instance exists ---
_find_instance() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
              "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].{ID:InstanceId,State:State.Name,IP:PublicIpAddress}' \
    --output json 2>/dev/null | grep -v '^null$' || echo "null"
}

_get_instance_id() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
              "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || true
}

# --- Step 3: update ~/.ssh/config with new IP ---
_update_ssh_config() {
  local new_ip="$1"
  _info "Updating ~/.ssh/config with IP $new_ip..."
  for host in ubuntu "ubuntu-tunnel"; do
    if grep -q "^Host ${host}$" "$SSH_CONFIG" 2>/dev/null; then
      sed -i '' "/^Host ${host}$/,/^Host /{s/HostName .*/HostName ${new_ip}/}" "$SSH_CONFIG"
    fi
  done
}

# --- Step 4: provision full stack ---
_provision() {
  _info "Provisioning VPC stack in $REGION..."

  local vpc_id subnet_id igw_id rt_id sg_id ami_id instance_id public_ip

  vpc_id=$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC_CIDR" \
    --query 'Vpc.VpcId' --output text)
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$vpc_id" --enable-dns-hostnames
  aws ec2 create-tags --region "$REGION" --resources "$vpc_id" \
    --tags Key=Name,Value=k3d-manager-vpc
  _info "VPC: $vpc_id"

  subnet_id=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc_id" \
    --cidr-block "$SUBNET_CIDR" --availability-zone "${REGION}a" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$subnet_id" \
    --map-public-ip-on-launch
  aws ec2 create-tags --region "$REGION" --resources "$subnet_id" \
    --tags Key=Name,Value=k3d-manager-subnet
  _info "Subnet: $subnet_id"

  igw_id=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$vpc_id" \
    --internet-gateway-id "$igw_id"
  _info "IGW: $igw_id"

  rt_id=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$vpc_id" \
    --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-route --region "$REGION" --route-table-id "$rt_id" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id" >/dev/null
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$rt_id" \
    --subnet-id "$subnet_id" >/dev/null
  _info "Route table: $rt_id"

  sg_id=$(aws ec2 create-security-group --region "$REGION" \
    --group-name k3d-manager-sg --description "k3d-manager EC2" --vpc-id "$vpc_id" \
    --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$sg_id" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$sg_id" \
    --protocol tcp --port 6443 --cidr 0.0.0.0/0 >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$sg_id" \
    --protocol -1 --port -1 --cidr 10.0.0.0/8 >/dev/null
  _info "Security group: $sg_id"

  # Import key pair (derive pub from .pem if .pub missing)
  if [[ ! -f "${KEY_PEM%.pem}.pub" ]]; then
    _info "Deriving public key from $KEY_PEM..."
    ssh-keygen -y -f "$KEY_PEM" > "${KEY_PEM%.pem}.pub"
  fi
  aws ec2 import-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --public-key-material "fileb://${KEY_PEM%.pem}.pub" >/dev/null 2>&1 || true

  ami_id=$(aws ec2 describe-images --region "$REGION" \
    --owners "$AMI_OWNER" \
    --filters "Name=name,Values=${AMI_FILTER}" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
  _info "AMI: $ami_id"

  instance_id=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$ami_id" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$subnet_id" \
    --security-group-ids "$sg_id" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
    --query 'Instances[0].InstanceId' --output text)
  _info "Instance launched: $instance_id — waiting for running state..."

  aws ec2 wait instance-running --region "$REGION" --instance-ids "$instance_id"
  public_ip=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

  _update_ssh_config "$public_ip"

  _info "Done."
  _info "  Instance: $instance_id"
  _info "  Public IP: $public_ip"
  _info "  SSH: ssh ubuntu 'hostname'"
  _info "  NOTE: k3s not yet installed — run Gemini rebuild spec next."
}

# --- Main ---
MODE="${1:-auto}"

_check_credentials

if [[ "$MODE" == "provision" ]]; then
  _provision
  exit 0
fi

_info "Checking for existing instance tagged '$INSTANCE_NAME'..."
INSTANCE_ID=$(_get_instance_id)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  if [[ "$MODE" == "check" ]]; then
    _info "No instance found. Run without arguments to provision."
    exit 1
  fi
  _info "No instance found — provisioning..."
  _provision
else
  STATE=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)
  PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

  if [[ "$STATE" == "stopped" ]]; then
    _info "Instance $INSTANCE_ID is stopped — starting..."
    aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
    PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  fi

  _update_ssh_config "$PUBLIC_IP"

  _info "Instance $INSTANCE_ID is $STATE at $PUBLIC_IP"
  _info "Checking k3s..."
  _k3s_check='k3s kubectl get nodes 2>/dev/null'
  if ssh -o ConnectTimeout=10 ubuntu "su -c '${_k3s_check}' root" 2>/dev/null; then
    _info "k3s is running."
  else
    _info "WARNING: k3s not responding — may need full rebuild. Spec: docs/plans/v0.9.4-gemini-rebuild-ubuntu-k3s-e2e.md"
  fi
fi
