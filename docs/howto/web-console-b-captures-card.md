# Web Console B captures — the short card

One page for the sittings. Every command runs on **m4**, in a plain Terminal (not tmux or screen), from the
k3d-manager folder on branch `k3d-manager-v1.47.0`. Details and reasons: [the full how-to](web-console-b-captures.md).
Never paste a token into chat or a command line; the kit asks for it hidden.

## Sitting 1 (~20 min, no iPad)

In the Cloudflare dashboard:

1. **Token:** My Profile → API Tokens → Create Token → Custom. Read permissions only: Access Apps and Policies,
   Access Certificates, Cloudflare Tunnel, Access Organizations/IdPs/Groups (account), DNS (your zone). TTL 24 h.
   Keep the page open.
2. **App:** Zero Trust → Access → Applications → Add → Self-hosted. Name **exactly `wcb-capture`**, domain
   `capture.<your-domain>`, browser-rendered SSH, session 6 h, GitHub only, one Allow rule for your GitHub email,
   short-lived certificate CA on.
3. **Tunnel:** Zero Trust → Networks → Tunnels → Add → Cloudflare managed. Name **exactly `k3dm-capture-tunnel`**,
   public hostname `capture.<your-domain>`, service `ssh://127.0.0.1:42723`. Keep the page open on the token.

In Terminal:

4. `bin/k3dm-wcb-capture api`
   - It asks for the **account ID**: the 32 characters in the dashboard address bar (`dash.cloudflare.com/<id>/…`).
   - If the capture token is not in the Keychain, it offers to store it: answer `y`, copy the token from step 1's
     page, paste at macOS's hidden prompt.
   - It finds the app, tunnel, hostname and team itself and prints `resolved` lines. If one says `not resolved`, it
     asks for that one value (see the how-to for where to find it).
   - `Capture gateway CA too? [y/N]`: Enter.
5. Copy the **tunnel connector token** from step 3's page now (copying the account ID replaced it in the clipboard).
6. `bin/k3dm-wcb-capture stage`
   - Type `yes` when the commit matches the GitHub branch tip.
   - Paste the connector token at the hidden prompt. It asks for sudo once.
   - **Save the `sudo …rootd.py …` line it prints** for sitting 2.

## Sitting 2 (~90 min, iPad on home Wi-Fi)

Three Terminal windows on m4:

1. Window 1: the saved `sudo …rootd.py …` line from stage.
2. Window 2: `bin/k3dm-wcb-capture browser-up`. It prints the connector line for window 3.
3. Window 3: paste the connector line it printed.

On the iPad, Safari → `https://capture.<your-domain>` and follow the screen: press Return to start each profile,
answer what Safari showed when the last session ended. Change nothing on m4 between logins. Stop at any profile and
resume later with `browser-up`.

Then, in window 2: `bin/k3dm-wcb-capture c8` (follow the four prompts), switch the app off in the dashboard and run
`bin/k3dm-wcb-capture api --after-disable` (no questions), then `bin/k3dm-wcb-capture c9` (timed dashboard steps).

## Sitting 3 (~30 min)

`bin/k3dm-wcb-capture root-checks`, then `bin/k3dm-wcb-capture c14-plain`.

## End (~15 min)

1. `bin/k3dm-wcb-capture collect`: read each file, `y` to keep.
2. `bin/k3dm-wcb-capture down`.
3. In the dashboard delete: the `wcb-capture` app (and `capture-other` if made), the `k3dm-capture-tunnel` tunnel,
   the capture token.
4. `security delete-generic-password -s k3dm-cloudflare-access-capture-token`
