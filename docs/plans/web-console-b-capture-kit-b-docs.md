# Web console part B capture kit — b: how-to and plan fixes

**Status:** SPEC — child of [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) rev 3; dispatch approved 2026-11-28; runs
alongside `a1` (no shared file)
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "agree, and itents approved" (parent K-E1..K-E10; this child carries K-E7b, intent unchanged)
**Approval:** operator, 2026-11-27 ("can this task split across Luna/Terra/Flash? worth a try?", then "go ahead")
**Release / branch:** v1.47.0, carried enabling work of v1.45.0 plan 4 part B, outside the cap (operator 2026-11-28, rule `docs/process/rules.md#enabling-work`); `k3d-manager-v1.47.0`
**Risk:** low (documentation only)
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`). **Verifier:** Claude, from Acceptance.

## Before You Start

1. Read the parent's `## Where and when`, `## Sittings`, §2, §6, §8, §10, §11, `## Decisions for the operator` and
   `## Method changes`. §11 is your scope.
2. Read `docs/plans/v1.45.0-web-console-b-captures.md` (safety rules, required token permissions, C1–C17) and the three
   capture directories `docs/captures/2026-11-19-web-console/`, `docs/captures/2026-11-19-web-console-c/`,
   `docs/captures/2026-11-21-web-console-a-live/`.
3. No command other than reading files and `make check-doc-links`. No Cloudflare dashboard or API access.

## Behaviour

Exactly the three items of the parent's §11:

1. `docs/howto/web-console-b-captures.md` (new): where and when (m4, plain Terminal at the desk, no tmux, no reboot
   between sitting 1 and `down`); the sittings table; step-by-step sitting 1 (create the read-only capture token with the
   plan's permission list and store it as `k3dm-cloudflare-access-capture-token` without displaying it; create the
   throwaway Access SSH app, its one-rule policy with a 6-hour session, and a remotely managed throwaway tunnel whose
   public hostname service is `ssh://127.0.0.1:42723`; save the connector token to `<(1)>/tunnel-token` mode `0600`);
   sitting 2 (three windows; what the iPad shows; the second throwaway app for C8 (d); the K2 (d) dummy-email step and
   its restore; that part A's `check` may show the tunnel item indeterminate while the connector runs); sitting 3; the
   cleanup checklist. Placeholders only (`<your-domain>`, `<login>`); no real hostname, id or email.
2. `docs/plans/v1.45.0-web-console-b-captures.md`: the "Capture status (2026-11-27)" section, the agent-only section
   correction, the `_wc_check_routes` design input, and a link to the kit, as §11 states.
3. `docs/plans/v1.45.0-web-console-a-console-sshd.md:202`: the P3/P5 sentence as §11 states. Change nothing else in the
   file.

## Files

| File | Change |
|---|---|
| `docs/howto/web-console-b-captures.md` | new |
| `docs/plans/v1.45.0-web-console-b-captures.md` | capture status section, stale lines, link |
| `docs/plans/v1.45.0-web-console-a-console-sshd.md` | line 202 sentence only |

## What NOT to Do

- No file outside `## Files`. No real hostname, account id, email or token. Do not change what any capture proves.

## Acceptance

```yaml
must:
  - id: K-M10b
    text: "the how-to and the two plan fixes match the parent's section 11"
must_not:
  - id: K-N7
    text: "the how-to or a plan change contains a real hostname, account id, email address or token (paired: the placeholders <your-domain> and <login> are present)"
evidence:
  - id: K-E7b
    proves: [K-M10b, K-N7]
    kind: offline
    command: "make check-doc-links rc 0 for the three files; grep -nEi '@[a-z0-9.-]+\\.[a-z]{2,}|[0-9a-f]{32}|eyJ' over the three files shows only example.invalid or none; git diff on v1.45.0-web-console-a-console-sshd.md touches only line 202's paragraph; Claude reads each change against section 11. Red control: put a real-looking email into the how-to — the grep shows it"
    intent: "The kit runs on the Mac's built-in Python, passes the repo's checks, and the step-by-step guide and the two corrected plans say what the kit actually does."
interface: "none"
```

## Worker definition of done

Report each command, its rc and the proving lines; list every error seen. Commit nothing; Claude lands.
