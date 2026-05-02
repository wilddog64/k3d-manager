# shellcheck shell=bash
# scripts/etc/playwright/vars.sh
#
# Single source of truth for Playwright automation constants.
# Sourced by scripts/plugins/acg.sh and scripts/plugins/gcp.sh; also read by
# scripts/playwright/*.js via argv (not by sourcing — node cannot source bash).
#
# CRITICAL: PLAYWRIGHT_AUTH_DIR holds the Chrome profile with your Pluralsight
# session cookies. Deleting it forces manual re-login and can trigger ACG
# bot-detection. Keep this path stable across versions.

export PLAYWRIGHT_URL_AWS="https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"
export PLAYWRIGHT_URL_GCP="https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"

export PLAYWRIGHT_CDP_HOST="127.0.0.1"
export PLAYWRIGHT_CDP_PORT="9222"

# Persistent Chrome profile used for CDP automation (shared with launchd job
# com.k3d-manager.chrome-cdp). Path must match _ACG_CHROME_CDP_AUTH_DIR in
# scripts/plugins/acg.sh.
export PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/profile"
