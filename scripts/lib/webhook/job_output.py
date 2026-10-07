"""Read bounded, redacted output from webhook job directories."""

from pathlib import Path

from webhook.redact import scrub_credentials


DEFAULT_MAX_CHARS = 2000


def _output_candidates(job_dir):
    """Return output files in deterministic precedence order for a job."""
    job_dir = Path(job_dir)
    is_make_job = (job_dir / "target").exists()
    if is_make_job:
        return (job_dir / "make.log", job_dir / "output", job_dir / "log")
    return (job_dir / "log", job_dir / "output")


def read_job_output(job_dir, redact=None, max_chars=DEFAULT_MAX_CHARS):
    """Read the preferred job output, bounded and redacted for external use."""
    for output_file in _output_candidates(job_dir):
        if not output_file.is_file():
            continue
        text = output_file.read_text(errors="replace")
        if not text:
            continue
        if max_chars > 0:
            text = text[-max_chars:]
        text = scrub_credentials(text)
        return redact(text) if redact else text
    return ""
