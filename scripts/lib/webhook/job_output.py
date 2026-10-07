"""Read bounded, redacted output from webhook job directories."""

from pathlib import Path
import re

from webhook.redact import scrub_credentials


DEFAULT_MAX_CHARS = 2000
def _output_candidates(job_dir):
    """Return output files in deterministic precedence order for a job."""
    job_dir = Path(job_dir)
    is_make_job = (job_dir / "target").exists()
    if is_make_job:
        return (job_dir / "make.log", job_dir / "output", job_dir / "log")
    return (job_dir / "log", job_dir / "output")


def _failure_excerpt(text, max_chars):
    """Keep multiple bounded failure summaries and the final tail."""
    lines = text.splitlines()
    if max_chars <= 0:
        return text
    marker_indexes = [
        index for index, line in enumerate(lines)
        if re.search(r"^\s*(?:not ok\b|FAILED\b|failure\b|error:\b|Traceback\b)", line, re.IGNORECASE)
    ]
    if not marker_indexes:
        return text[-max_chars:] if max_chars > 0 else text
    context_budget = max(600, int(max_chars * 0.65))
    tail_budget = max(0, max_chars - context_budget - 40)
    blocks = []
    for marker_index in marker_indexes[:20]:
        block = lines[marker_index:marker_index + 3]
        blocks.append("\n".join(block))
    context = "\n".join(blocks)[:context_budget]
    tail = text[-tail_budget:] if tail_budget else ""
    return f"[Failure context]\n{context}\n[Final output tail]\n{tail}"[:max_chars]


def read_job_output(job_dir, redact=None, max_chars=DEFAULT_MAX_CHARS):
    """Read the preferred job output, bounded and redacted for external use."""
    for output_file in _output_candidates(job_dir):
        if not output_file.is_file():
            continue
        text = output_file.read_text(errors="replace")
        if not text:
            continue
        if max_chars > 0:
            status_file = job_dir / "status"
            status = status_file.read_text(errors="replace").strip() if status_file.is_file() else ""
            is_failed_make = (job_dir / "target").exists() and status == "failed"
            text = _failure_excerpt(text, max_chars) if is_failed_make else text[-max_chars:]
        text = scrub_credentials(text)
        return redact(text) if redact else text
    return ""
