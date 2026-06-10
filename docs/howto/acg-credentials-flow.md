# ACG Credential Extraction — Flow Reference

This document traces every decision point in `acg_get_credentials` for debugging.

---

## Full Flow

```mermaid
sequenceDiagram
    participant Bash as acg_get_credentials (bash)
    participant Node as acg_credentials.js
    participant Chrome as Chrome / Chromium
    participant Tab as Pluralsight tab
    participant UI as Pluralsight ACG sandbox UI

    Bash->>Bash: verify `node` is installed
    alt Node missing
        Bash-->>Bash: ERROR: install Node.js
    end

    Bash->>Bash: verify Playwright module is installed
    alt Playwright missing
        Bash-->>Bash: ERROR: cd scripts/playwright && npm install
    end

    Bash->>Bash: probe 127.0.0.1:9222/json
    alt Chrome already running
        Bash-->>Node: continue with existing CDP session
    else Chrome not running
        Bash->>Chrome: _antigravity_launch
        alt macOS
            Chrome-->>Chrome: open -a "Google Chrome" --args<br/>--remote-debugging-port=9222<br/>--password-store=basic<br/>--user-data-dir=~/.local/share/k3d-manager/profile
        else Linux
            Chrome-->>Chrome: google-chrome / chromium<br/>--remote-debugging-port=9222<br/>--password-store=basic<br/>--user-data-dir=~/.local/share/k3d-manager/profile
        end
        Chrome->>Chrome: _antigravity_browser_ready 30
        alt Chrome did not become ready
            Chrome-->>Bash: ERROR: Chrome did not become ready
        end
    end

    Node->>Chrome: chromium.connectOverCDP(http://127.0.0.1:9222)
    alt CDP connection refused
        Node-->>Bash: ERROR: CDP connection refused
    end

    Node->>Tab: locate Pluralsight page
    alt no Pluralsight tab found
        Tab-->>Node: ERROR: no browser page available
    end

    Node->>UI: normalize navigation to targetUrl
    alt not on app.pluralsight.com
        UI-->>UI: page.goto(targetUrl)
    else already on exact targetUrl
        UI-->>UI: skip navigation (SPA auth preserved)
    else on pluralsight + cloud-sandboxes target
        UI-->>UI: SPA navigate (link click or location.assign)
    else on pluralsight + other path
        UI-->>UI: page.goto(targetUrl)
    end

    UI->>UI: wait for aria-busy to clear (30s, non-fatal)

    UI->>UI: check for "Sign In" button
    alt Sign In visible
        UI-->>UI: click Sign In
        UI-->>UI: wait for id.pluralsight.com
        UI-->>UI: fill email from PLURALSIGHT_EMAIL or wait for Password Manager
        UI-->>UI: click Continue if visible
        UI-->>UI: wait for password field
        UI-->>UI: click password field and wait 2s
        UI-->>UI: click Submit
        UI-->>UI: wait for redirect back to app.pluralsight.com
        alt redirect timeout
            UI-->>Bash: ERROR
        end
        UI->>UI: wait for aria-busy to clear again (30s, non-fatal)
    else already authenticated
        UI-->>UI: skip sign-in
    end

    UI->>UI: check for input[aria-label="Copyable input"]
    alt credentials panel already open
        UI-->>UI: skip Start/Open flow
    else credentials panel closed
        UI-->>UI: try buttons in order: Start Sandbox → Open Sandbox → Resume Sandbox
        alt Start Sandbox visible
            UI-->>UI: click Start Sandbox and wait 10s
        else Open Sandbox visible
            UI-->>UI: click Open Sandbox and wait 10s
            UI-->>UI: check nested Start Sandbox and click it if present
        else Resume Sandbox visible
            UI-->>UI: click Resume Sandbox and wait 10s
        else no matching buttons
            UI-->>UI: proceed anyway; credentials page may already be active
        end
    end

    UI->>UI: wait for input[aria-label="Copyable input"] (15s)
    alt credentials panel did not appear
        UI-->>Bash: ERROR: credentials panel did not appear
    end

    UI->>UI: extract Copyable input values
    alt access key and secret key found
        UI-->>Bash: stdout with AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
    else could not find AWS credentials
        UI-->>Bash: ERROR: Could not find AWS credentials
    end

    Bash->>Bash: perl extract AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
    alt access key or secret key empty
        Bash-->>Bash: FALLBACK: manual paste via pbpaste | ./scripts/k3d-manager acg_import_credentials
        Bash-->>Bash: return 1
    else credentials extracted
        Bash-->>Bash: _aws_write_credentials → ~/.aws/credentials
    end
```

---

## Common Failure Points

| Symptom | Likely cause | Fix |
|---|---|---|
| `CDP connection refused` | Chrome not running on 9222 | `acg_get_credentials` auto-launches; if it fails, check `ps aux \| grep chrome` for a conflicting Chrome instance without `--remote-debugging-port` |
| `No browser context found` | Chrome launched but no window/tab open | Open any tab in the `playwright-auth` Chrome window |
| `Chrome did not become ready` | macOS Keychain blocked Chrome startup | Confirm `--password-store=basic` is in the launch args; check `~/.local/share/k3d-manager/profile` exists |
| Sign-in loop / stuck on id.pluralsight.com | `PLURALSIGHT_EMAIL` not set + Password Manager didn't fire | Set `export PLURALSIGHT_EMAIL=you@example.com` before running |
| `credentials panel did not appear` | Sandbox not started, or UI changed | Manually click "Start Sandbox" in the Chrome window, then re-run |
| `Could not find AWS credentials` (positional fallback hit) | Pluralsight changed DOM order | Check `input[aria-label="Copyable input"]` count in DevTools; update positional index in `acg_credentials.js` |
| `playwright npm module not found` | npm install not run | `cd scripts/playwright && npm install` |

---

## Chrome Profile

The dedicated profile at `~/.local/share/k3d-manager/profile` keeps Pluralsight session cookies separate from your main Chrome. Once you sign in once, subsequent `acg_get_credentials` calls skip the sign-in flow entirely — as long as Chrome stays open.

To reset the session: `rm -rf ~/.local/share/k3d-manager/profile`
