"""Shared lookup for the pinned promtool used by offline PromQL tests."""

import os
import shutil
from pathlib import Path


def resolve_promtool() -> str:
    """Return the configured promtool or fail with the setup instruction."""
    candidates = []
    configured = os.environ.get("PROMTOOL")
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.append(Path.home() / ".local" / "bin" / "promtool")
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    on_path = shutil.which("promtool")
    if on_path:
        return on_path
    raise RuntimeError("promtool not found; run make machine-setup (installs promtool 3.1.0)")
