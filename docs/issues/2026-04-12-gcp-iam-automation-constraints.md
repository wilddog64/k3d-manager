# Issue: GCP IAM Automation - Platform and Security Constraints

**Date:** 2026-04-12
**Status:** MITIGATED / HYBRID STRATEGY
**Project:** k3d-manager (GCP Provider)

## Findings

After extensive testing of three different automation strategies (Playwright full automation, CLI-based pivot, and Chrome profile isolation), we have identified the following hard constraints:

1.  **Google Login Bot Detection:** Automated password entry and account selection via Playwright/Node.js are consistently blocked by Google's bot detection security (CAPTCHAs, "Verify it's you", and session redirects).
2.  **API Permission Restriction:** The ACG Sandbox user (`cloud_user_p_...`) is restricted from using the `setIamPolicy` API via the `gcloud` CLI or REST API. Attempting a CLI-based grant results in `Policy update access denied`.
3.  **UI Interstitial Requirements:** The GCP Console UI often requires manual "Terms of Service" acceptance or "Review updates" clicks before the "Grant access" buttons become enabled (turned from gray to blue).
4.  **Browser Identity Conflicts:** Using standard system browsers (like Safari) leads to identity mismatches where automation attempts to act on the user's personal Google account instead of the sandbox.

## Reached Strategy: The "Manual Bridge" Hybrid Flow

We have determined that a 100% "Zero-Touch" automation is not viable for this platform. The most robust and reliable path is a **Hybrid Workflow**:

1.  **Automated Extraction:** Gemini extracts the sandbox username, password, and project ID from the ACG dashboard.
2.  **Manual Login (The Bridge):** The user performs a one-time login in **Google Chrome** (not Safari) to bypass bot detection and establish the authenticated session.
3.  **Automated UI Grant (Surgical Latch-on):** Once the session is established and "Write" access is unlocked in the UI, Gemini latches onto the active Chrome tab via CDP to automate the tedious IAM table interactions (filling the SA email, selecting the `compute.admin` role, and saving).

## Evidence

### CLI API Restriction:
```text
ERROR: (gcloud.projects.add-iam-policy-binding) [cloud_user...] does not have permission to access projects instance [...:setIamPolicy]: Policy update access denied.
```

### UI Button State (Locked):
Playwright diagnostics confirmed the "Grant Access" button remains `aria-disabled="true"` until the user interacts with the console identity switcher or ToS banners.

## Recommended Follow-up

-   Update `scripts/plugins/gcp.sh` to guide the user through the "Manual Bridge" flow.
-   Ensure documentation explicitly mentions the requirement for Google Chrome as the secondary browser for GCP automation tasks.
