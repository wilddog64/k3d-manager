# shellcheck shell=bash
# Hostinger KVM VPS — CLUSTER_PROVIDER=k3s-hostinger
# Permanent single-node app-cluster host, provisioned out-of-band via the Hostinger panel.
# All values are env-overridable; override here or export before running.

HOSTINGER_HOST="${HOSTINGER_HOST:-srv1754834.hstgr.cloud}"
HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
