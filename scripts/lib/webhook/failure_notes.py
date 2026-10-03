"""Create small, redacted prior-art notes for failed local jobs."""

import datetime
import re

from webhook.redact import scrub_credentials


_ERROR_RE = re.compile(r"error|fail|fatal|traceback|exception", re.IGNORECASE)


def write_failure_note(job_dir, job_id, target, rc, timed_out=False, redact=lambda text: text):
    """Write one redacted failure note; return its path."""
    log_path = job_dir / "make.log"
    if not log_path.exists():
        log_path = job_dir / "output"
    text = log_path.read_text(errors="replace") if log_path.exists() else ""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    matches = [line for line in lines if _ERROR_RE.search(line)]
    error_line = (matches[-1] if matches else (lines[-1] if lines else "no output"))[:300]
    error_line = scrub_credentials(redact(error_line))
    date = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    result = f"timed out after {rc}s" if timed_out else f"failed (rc {rc})"
    note = (f"# Job failure: {target} ({job_id})\n\n"
            f"**Date:** {date}  **Target:** {target}  **Result:** {result}\n"
            f"**Signature:** {target}: {error_line}\n\n"
            "## Error\n\n"
            f"{error_line}\n\n"
            "## Fix\n\n"
            "(unknown — fill in when resolved)\n")
    path = job_dir / "failure.md"
    path.write_text(note)
    return path
