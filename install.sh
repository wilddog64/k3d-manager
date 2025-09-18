#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y shellcheck bats jq
