"""Scenario registry, isolated execution, redacted reports and retention."""
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
import json
import os
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

from webhook.redact import scrub_credentials
from .scenarios.k3dm_tests import BUGS, SCENARIOS
from .scenarios.jobs import run_job
from .scenarios.cleanup import cleanup_preview, cleanup_confirm, cleanup_vocabulary

@dataclass(frozen=True)
class Scenario:
    id: str
    fixture_revision: str
    requires: tuple
    deadline_s: int
    run: object

    def __iter__(self):
        return iter((self.id, self.requires, self.run))

    def __getitem__(self, index):
        return tuple(iter(self))[index]


def _scenario(entry):
    if isinstance(entry, Scenario):
        return entry
    sid, requires, fn = entry
    return Scenario(sid, "v1", tuple(requires), 30, fn)


REGISTRY = [_scenario(entry) for entry in SCENARIOS + [
    ("job-output", [], run_job),
    ("cleanup-preview", [], cleanup_preview),
    ("cleanup-ambient-confirm", [], cleanup_confirm),
    ("cleanup-vocabulary", [], cleanup_vocabulary),
]]
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,63}$")
RUN_RE = re.compile(r"^\d{8}T\d{6}Z-[0-9a-f]{8}$")
SECRET_RE = re.compile(r"https://hooks\.slack\.com/\S+|xox[abpors]-[A-Za-z0-9-]+|glsa_[A-Za-z0-9_]+")


@dataclass
class Context:
    run_dir: Path
    capabilities: set


def redact(value, extra_secrets=()):
    if isinstance(value, str):
        value = SECRET_RE.sub("***REDACTED***", scrub_credentials(value))
        for secret in extra_secrets:
            if secret:
                value = value.replace(secret, "***REDACTED***")
        return value
    if isinstance(value, list):
        return [redact(v, extra_secrets) for v in value]
    if isinstance(value, dict):
        return {redact(k, extra_secrets): redact(v, extra_secrets) for k, v in value.items()}
    return value


def _retention(root):
    now = datetime.now(timezone.utc)
    days = max(0, int(os.environ.get("K3DM_ACCEPTANCE_RETENTION_DAYS", "14")))
    max_bytes = max(1, int(os.environ.get("K3DM_ACCEPTANCE_MAX_MB", "500"))) * 1024 * 1024
    dirs = sorted((p for p in root.iterdir() if p.is_dir() and RUN_RE.fullmatch(p.name)), key=lambda p: p.stat().st_mtime)
    for path in dirs:
        if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < now - timedelta(days=days):
            shutil.rmtree(path)
    dirs = sorted((p for p in root.iterdir() if p.is_dir() and RUN_RE.fullmatch(p.name)), key=lambda p: p.stat().st_mtime)
    def total():
        return sum(f.stat().st_size for d in dirs if d.exists() for f in d.rglob("*") if f.is_file())
    while dirs and total() > max_bytes:
        shutil.rmtree(dirs.pop(0))


def run_scenarios(run_root=None, scenario_ids=None, registry=None, capabilities=None, extra_secrets=()):
    root = Path(run_root or os.environ.get("K3DM_ACCEPTANCE_RUN_ROOT", Path.home() / ".local/state/k3d-manager/acceptance")).expanduser()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    _retention(root)
    registered = [_scenario(entry) for entry in (REGISTRY if registry is None else registry)]
    selected = [entry for entry in registered if not scenario_ids or entry[0] in scenario_ids]
    started = datetime.now(timezone.utc).isoformat()
    run_dir = root / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + os.urandom(4).hex())
    run_dir.mkdir(mode=0o700)
    ctx = Context(run_dir, set(capabilities if capabilities is not None else ("promtool",) if shutil.which("promtool") else ()))
    results = []
    for sid, requires, func in selected:
        if not ID_RE.fullmatch(sid):
            raise ValueError("invalid scenario id")
        if not set(requires).issubset(ctx.capabilities):
            results.append({"id": sid, "outcome": "inconclusive", "cause": "environment_dependency", "assertions": [], "linked_bug": None})
            continue
        try:
            assertions = func(ctx)
            if any(a.get("inconclusive") for a in assertions):
                outcome, cause = "inconclusive", "environment_dependency"
            else:
                outcome = "passed" if all(a.get("passed") for a in assertions) and assertions else "failed"
                cause = "product_contract" if outcome == "failed" else "unknown"
            linked = BUGS.get(sid) if sid in BUGS and outcome == "failed" else None
            if linked:
                outcome = "known_failing"
            results.append({"id": sid, "outcome": outcome, "cause": cause, "assertions": assertions, "linked_bug": linked})
        except Exception as exc:
            results.append({"id": sid, "outcome": "inconclusive", "cause": "harness_error", "assertions": [{"name": "harness exception", "passed": False, "detail": repr(exc)}], "linked_bug": None})
    finished = datetime.now(timezone.utc).isoformat()
    total_assertions = sum(len(r["assertions"]) for r in results)
    expected_count = len(selected)
    passed = len(results) == expected_count and len(results) > 0 and total_assertions > 0 and all(r["outcome"] in {"passed", "known_failing"} for r in results)
    report = {"schema": 1, "source_sha": "unknown", "started": started, "finished": finished, "scenarios": results}
    payload = redact(report, extra_secrets)
    (run_dir / "report.json").write_text(json.dumps(payload, indent=2) + "\n")
    suite = ET.Element("testsuite", name="operator-acceptance", tests=str(total_assertions), failures=str(sum(not a.get("passed") for r in results for a in r["assertions"])), skipped=str(sum(r["outcome"] == "inconclusive" for r in results)))
    for scenario in results:
        case = ET.SubElement(suite, "testcase", name=redact(scenario["id"], extra_secrets))
        if scenario["outcome"] == "inconclusive":
            ET.SubElement(case, "skipped", message=redact(scenario["cause"], extra_secrets))
        for assertion in scenario["assertions"]:
            if not assertion.get("passed"):
                ET.SubElement(case, "failure", message=redact(assertion["name"], extra_secrets)).text = redact(assertion.get("detail", ""), extra_secrets)
    ET.ElementTree(suite).write(run_dir / "junit.xml", encoding="utf-8", xml_declaration=True)
    md = ["# Operator acceptance report", "", "Schema: 1", f"Assertions: {total_assertions}", "", "| Scenario | Outcome | Cause | Bug |", "|---|---|---|---|"]
    md.extend(f"| {r['id']} | {r['outcome']} | {r['cause']} | {r['linked_bug'] or ''} |" for r in results)
    (run_dir / "report.md").write_text(redact("\n".join(md) + "\n", extra_secrets))
    for path in run_dir.rglob("*"):
        path.chmod(0o700 if path.is_dir() else 0o600)
    run_dir.chmod(0o700)
    return run_dir, payload, passed
