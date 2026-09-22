"""File redacted Hermes E2E triage results in an isolated Git worktree."""

import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from hermes.e2e_triage import redact

_BRANCH = re.compile(r"^k3d-manager-v\d+\.\d+\.\d+$")
_HINTS = {
    "service-unreachable": "the service is not in the Tier 1 substrate or never became ready; check `scripts/etc/e2e/kustomization.yaml` and the rollout wait list.",
    "contract-drift": "the response shape differs from the test's expectation; compare the substrate image pin with the `shopping-cart-e2e-tests` image and the service's API.",
    "timeout": "check substrate readiness and runner load (`make e2e-runner-health RUNNER=m2`).",
    "auth": "the request was rejected by authn/authz, not by the service's business logic; check the Keycloak realm client, the token audience, and whether `secret/keycloak/clients` matches what the test requests.",
    "assertion": "a behaviour change; read the failing test.",
    "harness": "the run did not reach Playwright; read the dispatch transcript.",
}


def _run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=120, check=False)


def _first_line(value):
    return redact((value or "").strip().splitlines()[0] if value else "unknown error")


def _branch(repo):
    result = _run(["git", "-C", str(repo), "branch", "--show-current"])
    name = result.stdout.strip()
    return name if result.returncode == 0 and _BRANCH.fullmatch(name) else ""


def _worktree(repo, root):
    path = Path(root) / "bugs-worktree"
    if not path.exists():
        result = _run(["git", "-C", str(repo), "worktree", "add", "--detach", str(path)])
        if result.returncode != 0:
            return None, f"worktree failed: {_first_line(result.stderr)}"
    return path, ""


def _update_worktree(worktree, branch):
    for command in (("fetch", "origin", branch), ("checkout", "--force", "--detach", f"origin/{branch}")):
        result = _run(["git", "-C", str(worktree), *command])
        if result.returncode != 0:
            return _first_line(result.stderr)
    return ""


def _status(path):
    match = re.search(r"^\*\*Status:\*\*\s*(.*)$", path.read_text(), re.M)
    return match.group(1) if match else ""


def _date(slot):
    return slot[:10] if re.fullmatch(r"\d{4}-\d{2}-\d{2}", slot[:10]) else datetime.now(timezone.utc).date().isoformat()


def _lines(group):
    lines = []
    for item in group.get("titles", [])[:10]:
        lines.append(f"- `{redact(item.get('file'))}` — {redact(item.get('title'))}")
    extra = group.get("count", 0) - len(group.get("titles", [])[:10])
    if extra > 0:
        lines.append(f"- …and {extra} more")
    return "\n".join(lines) or "- No individual test title was available"


def _status_doc(group, run, branch, date):
    return f'''# Bug: cluster status {redact(group["kind"])} — {redact(group["target"])}

**Branch:** `{branch}`
**Filed:** {date} by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Source:** `bin/cluster-status --json`
**Sample:** `{redact(run.get("run_id", "unknown"))}`
**Counts:** {redact(str(run.get("summary", {})))}

## Failing checks ({group.get("count", 0)})
{_lines(group)}

## Sample errors
{chr(10).join(f"- {redact(sample)}" for sample in group.get("samples", [])[:3]) or "- No sample error was available"}

## Next step
Verify the failing check and its underlying service. SSO and credential failures require
human investigation; existing repair proposals still require approval.
'''


def _doc(group, run, branch, date):
    if run.get("source") == "status":
        return _status_doc(group, run, branch, date)
    summary = run.get("summary", {})
    return f'''# Bug: e2e {group["kind"]} — {group["target"]}

**Branch:** `{branch}`
**Filed:** {date} by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `{run.get("run_id", "unknown")}`, runner `m2`, tier `vcluster`, {summary.get("passed", 0)} passed / {summary.get("failed", group.get("count", 0))} failed / {summary.get("total", 0)} total
**Runner commit:** `{summary.get("commit", "unknown")}`

## Failing tests ({group.get("count", 0)})
{_lines(group)}

## Sample errors
{chr(10).join(f"- {redact(sample)}" for sample in group.get("samples", [])[:3]) or "- No sample error was available"}

## Triage hint
{_HINTS.get(group["kind"], _HINTS["assertion"])}

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
'''


def _reopen(path, group, run, date):
    text = path.read_text()
    source = "cluster status sample" if run.get("source") == "status" else "e2e run"
    unit = "check(s)" if run.get("source") == "status" else "test(s)"
    text = re.sub(r"^\*\*Status:\*\*.*$", f"**Status:** REOPENED {date} — recurred in Hermes {source} {redact(run.get('run_id', 'unknown'))}", text, flags=re.M)
    samples = "\n".join(f"- {redact(value)}" for value in group.get("samples", [])[:3])
    path.write_text(text + f"\n## Recurrence {date} (run {run.get('run_id', 'unknown')})\n\n"
                    f"{group.get('count', 0)} failing {unit}.\n{_lines(group)}\n\n{samples}\n")


def _commit_push(worktree, paths, slot, run, branch):
    add = _run(["git", "-C", str(worktree), "add", "--", *map(str, paths)])
    if add.returncode != 0:
        return f"commit blocked by pre-commit: {_first_line(add.stderr)}"
    source = "status" if run.get("source") == "status" else "e2e"
    commit = _run(["git", "-C", str(worktree), "commit", "-m", f"docs(bugs): Hermes {source} triage {slot} (run {redact(run.get('run_id', 'unknown'))})", "-m", "Filed-By: k3dm-hermes"])
    if commit.returncode != 0:
        return f"commit blocked by pre-commit: {_first_line(commit.stderr or commit.stdout)}"
    push = _run(["git", "-C", str(worktree), "push", "origin", f"HEAD:refs/heads/{branch}"])
    if push.returncode == 0:
        return "pushed"
    first = _first_line(push.stderr)
    _run(["git", "-C", str(worktree), "fetch", "origin", branch])
    rebase = _run(["git", "-C", str(worktree), "rebase", f"origin/{branch}"])
    retry = _run(["git", "-C", str(worktree), "push", "origin", f"HEAD:refs/heads/{branch}"])
    return "pushed after rebase" if rebase.returncode == 0 and retry.returncode == 0 else f"push failed: {first}"


def file_bugs(repo_root, groups, run, slot, hermes_root=None):
    """Write only new/reopened groups, committing only in Hermes' own worktree."""
    repo = Path(repo_root)
    branch = _branch(repo)
    if not branch:
        return {"groups": [], "push": "bugs not filed: repo not on a release branch"}
    root = Path(hermes_root) if hermes_root else Path.home() / ".k3dm/hermes"
    worktree, error = _worktree(repo, root)
    if error:
        return {"groups": [], "push": error}
    error = _update_worktree(worktree, branch)
    if error:
        return {"groups": [], "push": error}
    bug_dir, date = worktree / "docs/bugs", _date(slot)
    changed, outcomes = [], []
    for group in groups:
        matches = sorted(bug_dir.glob(f"*-{group['slug']}.md"))
        if not matches:
            path = bug_dir / f"{date}-{group['slug']}.md"
            path.write_text(_doc(group, run, branch, date))
            changed.append(path.relative_to(worktree)); outcomes.append({"status": "created", "path": str(path.relative_to(worktree)), **group})
        elif _status(matches[0]).startswith(("FIXED", "CLOSED")):
            _reopen(matches[0], group, run, date)
            changed.append(matches[0].relative_to(worktree)); outcomes.append({"status": "reopened", "path": str(matches[0].relative_to(worktree)), **group})
        else:
            outcomes.append({"status": "ongoing", "path": str(matches[0].relative_to(worktree)), **group})
    return {"groups": outcomes, "push": _commit_push(worktree, changed, slot, run, branch) if changed else "no changes"}
