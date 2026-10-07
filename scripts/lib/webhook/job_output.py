"""Read bounded, redacted output from webhook job directories."""

from pathlib import Path
import re

from webhook.redact import scrub_credentials


DEFAULT_MAX_CHARS = 2000
_FAILURE_MARKER_RE = re.compile(
    r"(?:^|\s)(?:not ok\b|failed\b|failure\b|error:\b|traceback\b|"
    r"assertionerror\b|make:\s+\*\*\*)",
    re.IGNORECASE,
)


def _output_candidates(job_dir):
    """Return output files in deterministic precedence order for a job."""
    job_dir = Path(job_dir)
    is_make_job = (job_dir / "target").exists()
    if is_make_job:
        return (job_dir / "make.log", job_dir / "output", job_dir / "log")
    return (job_dir / "log", job_dir / "output")


def _failure_excerpt(text, max_chars):
    """Keep an early failure marker and the final tail within the output budget."""
    lines = text.splitlines()
    marker_index = next(
        (index for index, line in enumerate(lines) if _FAILURE_MARKER_RE.search(line)),
        None,
    )
    if marker_index is None or max_chars <= 0:
        return text[-max_chars:] if max_chars > 0 else text
    context_budget = max(400, max_chars // 2)
    tail_budget = max(0, max_chars - context_budget - 40)
    context_lines = lines[max(0, marker_index - 2):marker_index + 9]
    context = "\n".join(context_lines)[:context_budget]
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
