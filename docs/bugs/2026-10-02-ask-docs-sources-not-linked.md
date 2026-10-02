# `/ask-docs` lists its sources as bare paths, with no link to open them

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. The reader has to copy a path such as `docs/bugs/2026-10-01-….md` and find it by hand
before they can check what the answer is based on.
**Status:** OPEN
**Related:** `docs/bugs/2026-10-01-ask-answers-not-threaded-and-ask-docs-no-fast-mode.md`, which added
`--sources` mode.

## Cause

`_reply` in `scripts/lib/webhook/ask_docs.py` renders `Sources:` followed by one raw path per line.
`wilddog64/k3d-manager` is a public repo, so each path can be a GitHub link.

## Fix (`scripts/lib/webhook/ask_docs.py` only)

1. Settings, read at call time:
   - `K3DM_ASK_DOCS_REPO_URL`, default `https://github.com/wilddog64/k3d-manager`. Strip any trailing `/`.
   - `K3DM_ASK_DOCS_LINK_REF`. When it is unset, use the branch that `REPO_ROOT` has checked out:
     - read it with `git -C <REPO_ROOT> rev-parse --abbrev-ref HEAD` through `subprocess.run`, with a list argv, a 5 s timeout and `check=False`;
     - cache the result for the process lifetime;
     - on any failure, an empty result, or `HEAD` (detached), use `main`.
   - The ref is the branch the excerpts were read from, so a doc filed on the release branch resolves before it merges.
2. Add `_doc_link(path)`:
   - Returns `<{repo_url}/blob/{ref}/{quoted_path}|{path}>`, where `quoted_path` is
     `urllib.parse.quote(path, safe="/")` and `ref` is quoted the same way.
   - It is called only for paths that already passed `_allowed_path`.
   - If the path contains any of `<`, `>`, `|` or a newline, return the plain path.
3. `_reply`: each source line becomes `_doc_link(path)`.
   - `Sources: none` is unchanged.
   - The existing budget still holds: `MAX_REPLY_CHARS` is computed with the **linked** source lines, so the
     total stays at or under 3000 and a link is never cut in half.
4. `--sources` mode: each `Top matching documents:` row shows the path as `_doc_link(path)`. The score,
   date and title are unchanged.
5. Do not change retrieval, scoring, the allowlist, redaction, the prompt, or the threading code.
6. Docs: in `docs/howto/slack-slash-commands.md`, under `/ask-docs`, add one line:
   - sources are links to GitHub at the webhook's checked-out branch;
   - `K3DM_ASK_DOCS_LINK_REF` overrides the branch.

## Tests (`scripts/tests/bin/test_ask_docs.py`, stubbed retrieval and model, no network)

1. A summarised answer: each source renders as
   `<https://github.com/wilddog64/k3d-manager/blob/<ref>/docs/bugs/x.md|docs/bugs/x.md>`.
   Set the ref with `K3DM_ASK_DOCS_LINK_REF`.
2. `--sources` mode: the rows contain the same link.
3. Ref fallback:
   - with the env var unset and a stubbed `subprocess.run` returning `HEAD`, the link uses `main`;
   - when it returns a branch name, the link uses that branch;
   - when it raises, the link uses `main`.
4. With very long prose, the reply is at most `MAX_REPLY_CHARS`, and every source link is intact. Assert
   that the `<` and `>` counts are equal, and that every source path appears.
5. A path containing `|` (stub `_allowed_path` to True) renders as plain text, not a link.
6. Existing ask-docs tests stay green. Update any that asserted bare paths so they assert the links.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) budget computed from the unlinked source lines → test 4 is red;
(b) the `HEAD` fallback removed → test 3 is red.

## Rules

- `pytest scripts/tests/bin/test_ask_docs.py scripts/tests/bin/test_webhook_ask_docs_thread.py` and `pytest scripts/tests/bin/` are green.
- No Slack, network, or git writes. Leave the changes uncommitted. Do not touch `CHANGELOG.md`.
- Update this doc: Status FIXED (pending deploy), plus a short Resolution section.

## Rollout

`make restart-webhook`. No relay change.
