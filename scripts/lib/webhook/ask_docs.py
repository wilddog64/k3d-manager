"""Read-only Slack Q&A over a bounded, redacted documentation corpus."""

import logging
import os
import re
from pathlib import Path

from hermes import prior_art
from webhook import agent
from webhook.redact import scrub_credentials

LOGGER = logging.getLogger(__name__)
REPO_ROOT = prior_art.REPO_ROOT
RETURNABLE_DIRS = ("docs/bugs/", "docs/issues/", "docs/plans/", "docs/retro/")
ASK_DOCS_MIN_SCORE = float(os.environ.get("K3DM_ASK_DOCS_MIN_SCORE", "0.60"))
MAX_EXCERPT_CHARS = 600
MAX_REPLY_CHARS = 3000
_IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_PHONE_RE = re.compile(r"(?<!\w)(?:\+?\d[\d .()\-]{7,}\d)(?!\w)")


def _scrub(text):
    text = scrub_credentials(text)
    text = _IP_RE.sub("[REDACTED IP]", text)
    return _PHONE_RE.sub("[REDACTED PHONE]", text)


def _allowed_path(path):
    normalized = str(path).replace("\\", "/")
    if not any(normalized.startswith(directory) for directory in RETURNABLE_DIRS):
        return False
    candidate = (REPO_ROOT / normalized).resolve()
    return any(candidate.is_relative_to((REPO_ROOT / directory).resolve()) for directory in RETURNABLE_DIRS)


def _excerpt(path, title):
    file_path = REPO_ROOT / path
    if not file_path.is_file():
        return None
    try:
        text = file_path.read_text(errors="replace")[:MAX_EXCERPT_CHARS]
    except OSError:
        return None
    return _scrub(f"Title: {title}\n{text}")


def _sources(results):
    kept = []
    excerpts = []
    for score, path, title in results:
        if score < ASK_DOCS_MIN_SCORE or not _allowed_path(path):
            continue
        excerpt = _excerpt(path, title)
        if excerpt is None:
            continue
        kept.append(path)
        excerpts.append(excerpt)
    return kept, excerpts


def _reply(prose, paths, *, scrub_prose=True):
    source_lines = "Sources: none" if not paths else "Sources:\n" + "\n".join(paths)
    if not prose:
        prose = "Could not summarise — read the sources directly."
    if scrub_prose:
        prose = _scrub(prose)
    available = MAX_REPLY_CHARS - len(source_lines) - 2
    if available < 0:
        available = 0
    return prose[:available].rstrip() + "\n\n" + source_lines


def answer(question, *, retrieve=prior_art.search, model=agent._call_gemini, k=5, summarise=True):
    """Answer from retrieved documentation, always retaining a verifiable source list."""
    question = agent._sanitize_question(question or "")
    if not question:
        return _reply("Question rejected — too long or contains disallowed patterns.", [])
    try:
        results = retrieve(question, k=k)
    except Exception as exc:
        LOGGER.warning("ask-docs retrieval unavailable: %s", type(exc).__name__)
        return _reply("No matching documents — document search is unavailable right now.", [])
    paths, excerpts = _sources(results)
    if not excerpts:
        return _reply("No matching documents for that question.", [])
    if not summarise:
        lines = ["Top matching documents:"]
        lines.extend(f"{score:.2f}  {path} — {_scrub(title)}" for score, path, title in results
                     if score >= ASK_DOCS_MIN_SCORE and _allowed_path(path)
                     and path in paths)
        return _reply("\n".join(lines), paths, scrub_prose=False)
    prompt = (
        "Answer the question only from the documentation excerpts below. If they do not contain "
        "the answer, say so plainly. Do not invent facts or use tools.\n\n"
        f"Question: {question}\n\n" + "\n\n---\n\n".join(excerpts)
    )
    try:
        prose = model(prompt)
    except Exception as exc:
        LOGGER.warning("ask-docs model unavailable: %s", type(exc).__name__)
        prose = ""
    return _reply(prose, paths)
