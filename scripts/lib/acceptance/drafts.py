"""Local-only bug draft generation and fingerprint deduplication for acceptance runs."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re

from hermes.prior_art import RetrievalUnavailable, search as prior_art_search
from .runner import RUN_RE, redact as runner_redact

ROOT = Path(__file__).resolve().parents[3]
_REQUEST_ID_RE = re.compile(r"\b\d{8}T\d{6}Z-[a-z0-9][a-z0-9-]{0,63}\b")
_ISO_TS_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b")
_WS_RE = re.compile(r"\s+")


def scrub_text(value, extra_secrets=()):
    """Apply runner credential redaction plus any runtime canary secrets."""
    redacted = runner_redact(value)
    if isinstance(redacted, str):
        for secret in extra_secrets:
            if secret:
                redacted = redacted.replace(secret, "***REDACTED***")
        return redacted
    if isinstance(redacted, list):
        return [scrub_text(item, extra_secrets) for item in redacted]
    if isinstance(redacted, dict):
        return {
            scrub_text(key, extra_secrets): scrub_text(val, extra_secrets)
            for key, val in redacted.items()
        }
    return redacted


def normalise_field(value, extra_secrets=()):
    """Normalise expected/actual text so transient timestamps do not alter fingerprints."""
    text = scrub_text(str(value or ""), extra_secrets)
    text = _REQUEST_ID_RE.sub("<request-id>", text)
    text = _ISO_TS_RE.sub("<timestamp>", text)
    return _WS_RE.sub(" ", text).strip().lower()


def fingerprint_failure(scenario_id, assertion, extra_secrets=()):
    """Compute the 12-hex sha256 fingerprint for a failed product_contract assertion."""
    assertion_id = scrub_text(
        str(assertion.get("id") or assertion.get("name") or "assertion").strip(),
        extra_secrets,
    )
    expected_raw = assertion.get("expected", "passed=true")
    actual_raw = assertion["actual"] if "actual" in assertion else assertion.get("detail", "passed=false")
    norm_expected = normalise_field(expected_raw, extra_secrets)
    norm_actual = normalise_field(actual_raw, extra_secrets)
    material = f"{scenario_id}\n{assertion_id}\n{norm_expected}\n{norm_actual}".encode("utf-8")
    digest = hashlib.sha256(material).hexdigest()[:12]
    return digest, assertion_id, norm_expected, norm_actual


def _display_path(path, repo_root):
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except (OSError, ValueError):
        return str(path)


def _find_seen_before(fingerprint, run_root, current_run_dir, bugs_dir, repo_root):
    if bugs_dir.is_dir():
        for bug_doc in sorted(bugs_dir.glob("*.md")):
            if not bug_doc.is_file():
                continue
            try:
                content = bug_doc.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if fingerprint in bug_doc.name or fingerprint in content:
                return _display_path(bug_doc, repo_root)
    if run_root.is_dir():
        for entry in sorted(run_root.iterdir()):
            if entry == current_run_dir or not entry.is_dir() or not RUN_RE.fullmatch(entry.name):
                continue
            candidate = entry / "drafts" / f"{fingerprint}.md"
            if candidate.is_file():
                return str(candidate)
    return None


def _lookup_prior_art(query_text, search_fn, extra_secrets=()):
    fn = prior_art_search if search_fn is None else search_fn
    try:
        rows = fn(query_text, k=3)
    except RetrievalUnavailable as exc:
        return "retrieval_unavailable", [], scrub_text(str(exc) or "retrieval unavailable", extra_secrets)
    cleaned = []
    for score, path, title in list(rows or [])[:3]:
        cleaned.append({
            "score": round(float(score), 4),
            "path": scrub_text(str(path), extra_secrets),
            "title": scrub_text(str(title), extra_secrets),
        })
    return "ok", cleaned, ""


def _prior_art_header_line(with_prior_art, status, candidates, error_detail):
    if not with_prior_art:
        return "exact-fingerprint check: none; prior_art.search not run"
    if status == "retrieval_unavailable":
        return f"exact-fingerprint check: none; retrieval unavailable ({error_detail})"
    if not candidates:
        return "exact-fingerprint check: none; none above threshold"
    formatted = ", ".join(f"{item['path']} ({item['score']:.3f})" for item in candidates)
    return f"exact-fingerprint check: none; advisory candidates: {formatted}"


def _render_draft(
    scenario_id,
    assertion,
    assertion_id,
    fingerprint,
    norm_expected,
    norm_actual,
    run_id,
    date_str,
    with_prior_art,
    pa_status,
    pa_candidates,
    pa_error,
    extra_secrets=(),
    caught_by="live check",
):
    assertion_name = scrub_text(str(assertion.get("name") or assertion_id), extra_secrets)
    detail = scrub_text(str(assertion.get("detail") or norm_actual), extra_secrets)
    prior_art_line = _prior_art_header_line(with_prior_art, pa_status, pa_candidates, pa_error)
    lines = [
        f"# Bug draft: operator-acceptance `{scenario_id}` failed `{assertion_id}`",
        "",
        "**Status:** OPEN — captured, not triaged",
        "**Priority:** P3 (proposed)",
        "**Introduced by:** unknown",
        f"**Should have been caught by:** {caught_by}",
        "**Introducing change reviewed:** unknown",
        f"**Waiting on:** operator decision — since {date_str}",
        "**Classified:** pending",
        f"**Prior art:** {prior_art_line}",
        f"**Filed:** {date_str}, operator-acceptance run {run_id}",
        f"**Fingerprint:** {fingerprint}",
        "",
        "## Symptom",
        "",
        f"- Scenario: `{scenario_id}`",
        f"- Assertion: `{assertion_name}` (`{assertion_id}`)",
        f"- Expected: `{norm_expected}`",
        f"- Actual: `{norm_actual}`",
        f"- Detail: {detail}",
    ]
    if pa_candidates:
        lines.extend(["", "## Advisory prior art", ""])
        for item in pa_candidates:
            lines.append(f"- `{item['path']}` ({item['score']:.3f}) — {item['title']}")
    return scrub_text("\n".join(lines) + "\n", extra_secrets)


def process_run_drafts(
    run_dir,
    report,
    *,
    run_root=None,
    bugs_dir=None,
    repo_root=None,
    with_prior_art=False,
    search_fn=None,
    extra_secrets=(),
    caught_by="live check",
    now=None,
):
    """Write local-only bug drafts for failed product_contract scenarios and update the run report."""
    run_dir = Path(run_dir)
    effective_root = Path(run_root).expanduser() if run_root is not None else run_dir.parent
    effective_repo = Path(repo_root) if repo_root is not None else ROOT
    effective_bugs = Path(bugs_dir) if bugs_dir is not None else (effective_repo / "docs" / "bugs")
    current_dt = now or datetime.now(timezone.utc)
    date_str = current_dt.strftime("%Y-%m-%d")

    failing = [
        scenario for scenario in report.get("scenarios", [])
        if scenario.get("outcome") == "failed" and scenario.get("cause") == "product_contract"
    ]
    if not failing and not with_prior_art:
        return []

    draft_records = []
    md_sections = []
    prior_art_notes = []

    if with_prior_art and not failing:
        pa_status, pa_candidates, pa_error = _lookup_prior_art(
            "operator acceptance k3dm-tests",
            search_fn,
            extra_secrets=extra_secrets,
        )
        if pa_status == "retrieval_unavailable":
            prior_art_notes.append(f"retrieval unavailable: {pa_error}")
        elif pa_candidates:
            for item in pa_candidates:
                prior_art_notes.append(f"advisory candidate: {item['path']} ({item['score']:.3f}) — {item['title']}")
        else:
            prior_art_notes.append("no advisory candidates")

    for scenario in failing:
        scenario_id = str(scenario["id"])
        assertions = scenario.get("assertions") or []
        first_failed = next(
            (item for item in assertions if not item.get("passed")),
            {"id": scenario_id, "name": scenario_id, "passed": False, "detail": "scenario failed"},
        )
        fingerprint, assertion_id, norm_expected, norm_actual = fingerprint_failure(
            scenario_id,
            first_failed,
            extra_secrets=extra_secrets,
        )
        pa_status, pa_candidates, pa_error = ("not_run", [], "")
        if with_prior_art:
            query = f"{scenario_id} {assertion_id} {norm_actual}"
            pa_status, pa_candidates, pa_error = _lookup_prior_art(
                query,
                search_fn,
                extra_secrets=extra_secrets,
            )
            if pa_status == "retrieval_unavailable":
                prior_art_notes.append(f"{scenario_id}: retrieval unavailable: {pa_error}")
            else:
                for item in pa_candidates:
                    prior_art_notes.append(
                        f"{scenario_id}: advisory candidate: {item['path']} ({item['score']:.3f}) — {item['title']}"
                    )

        seen_path = _find_seen_before(
            fingerprint,
            effective_root,
            run_dir,
            effective_bugs,
            effective_repo,
        )
        if seen_path is not None:
            clean_seen = scrub_text(seen_path, extra_secrets)
            draft_records.append({
                "scenario": scenario_id,
                "fingerprint": fingerprint,
                "status": "seen_before",
                "path": clean_seen,
                "prior_art_status": pa_status,
                "prior_art": pa_candidates,
            })
            md_sections.append(f"- `{scenario_id}` (`{fingerprint}`): seen before: {clean_seen}")
            continue

        drafts_dir = run_dir / "drafts"
        drafts_dir.mkdir(mode=0o700, exist_ok=True)
        os.chmod(drafts_dir, 0o700)
        draft_path = drafts_dir / f"{fingerprint}.md"
        draft_body = _render_draft(
            scenario_id=scenario_id,
            assertion=first_failed,
            assertion_id=assertion_id,
            fingerprint=fingerprint,
            norm_expected=norm_expected,
            norm_actual=norm_actual,
            run_id=run_dir.name,
            date_str=date_str,
            with_prior_art=with_prior_art,
            pa_status=pa_status,
            pa_candidates=pa_candidates,
            pa_error=pa_error,
            extra_secrets=extra_secrets,
            caught_by=caught_by,
        )
        draft_path.write_text(draft_body, encoding="utf-8")
        os.chmod(draft_path, 0o600)
        rel_draft = f"drafts/{fingerprint}.md"
        draft_records.append({
            "scenario": scenario_id,
            "fingerprint": fingerprint,
            "status": "written",
            "path": rel_draft,
            "prior_art_status": pa_status,
            "prior_art": pa_candidates,
        })
        md_sections.append(f"- `{scenario_id}` (`{fingerprint}`): draft written: {rel_draft}")

    report["drafts"] = scrub_text(draft_records, extra_secrets)
    if with_prior_art:
        report["prior_art"] = scrub_text(prior_art_notes, extra_secrets)
    scrubbed_report = scrub_text(report, extra_secrets)
    report.clear()
    report.update(scrubbed_report)

    report_json_path = run_dir / "report.json"
    report_json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    os.chmod(report_json_path, 0o600)

    report_md_path = run_dir / "report.md"
    existing_md = report_md_path.read_text(encoding="utf-8") if report_md_path.is_file() else ""
    extra_md = []
    if md_sections:
        extra_md.extend(["", "## Bug drafts", "", *md_sections])
    if prior_art_notes:
        extra_md.extend(["", "## Prior art", "", *(f"- {note}" for note in prior_art_notes)])
    if extra_md:
        updated_md = scrub_text(existing_md.rstrip("\n") + "\n" + "\n".join(extra_md) + "\n", extra_secrets)
        report_md_path.write_text(updated_md, encoding="utf-8")
        os.chmod(report_md_path, 0o600)

    return report["drafts"]
