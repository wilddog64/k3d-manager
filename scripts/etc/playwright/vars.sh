# scripts/etc/playwright/vars.sh
# 
# CRITICAL: The PLAYWRIGHT_PROFILE_DIR stores your Pluralsight/GCP session cookies.
# Do not delete this directory unless you want to perform manual re-authentication.

PLAYWRIGHT_URL_AWS="https://app.pluralsight.com/cloud-playground/cloud-sandboxes"
PLAYWRIGHT_URL_GCP="https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"

PLAYWRIGHT_CDP_HOST="127.0.0.1"
PLAYWRIGHT_CDP_PORT="9222"

# Persistent profile used for automation
PLAYWRIGHT_PROFILE_DIR="${HOME}/.local/share/k3d-manager/profile"
