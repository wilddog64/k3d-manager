"""Scrub credential-shaped values from untrusted command output."""

import re


SENSITIVE_KEY_WORDS = frozenset((
    "password", "passwd", "secret", "token", "api_key", "api-key", "credential",
))
_MARKER = "***REDACTED***"
_KEY_VALUE_RE = re.compile(
    r"(?i)\b([\w.-]*(?:password|passwd|secret|token|api[_-]?key|credential)s?)"
    r"(\"?)(\s*[:=]\s*)(?:\"([^\"]*)\"|'([^']*)'|((Bearer\s+)?\S+))"
)
_BEARER_RE = re.compile(r"(?i)\b(Bearer\s+)\S+")
_BASIC_RE = re.compile(r"(?i)\b(Basic\s+)\S+")
_JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")
_URL_USERINFO_RE = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*://[^/\s:@]*:)([^@\s]+)(@)")
_VAULT_RE = re.compile(r"\b(?:hvs|s)\.[A-Za-z0-9]{24,}")
_STRIPE_RE = re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9_]+")
_GITHUB_RE = re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]+")
_ENV_HEADER_RE = re.compile(r"^(\s*)Environment:")
_ENV_ENTRY_RE = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_.-]*)(:\s*)(.*)$")
_SENSITIVE_ENV_NAME_RE = re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key|credential|dsn|_url$)")


def scrub_credentials(text):
    """Replace credential-shaped values while preserving useful prefixes."""
    if not isinstance(text, str) or not text:
        return text
    def _replace_key_value(match):
        key, closing_quote, delimiter, double_value, single_value, bare_value, bearer = match.groups()
        if double_value is not None:
            value = f'"{_MARKER}"'
        elif single_value is not None:
            value = f"'{_MARKER}'"
        elif bearer is not None:
            value = f"{bearer}{_MARKER}"
        else:
            value = _MARKER
        return key + closing_quote + delimiter + value

    text = _KEY_VALUE_RE.sub(_replace_key_value, text)
    text = _BEARER_RE.sub(lambda match: match.group(1) + _MARKER, text)
    text = _BASIC_RE.sub(lambda match: match.group(1) + _MARKER, text)
    text = _URL_USERINFO_RE.sub(r"\1" + _MARKER + r"\3", text)
    for pattern in (_JWT_RE, _VAULT_RE, _STRIPE_RE, _GITHUB_RE):
        text = pattern.sub(_MARKER, text)
    return text


def mask_env_values(text):
    """Mask literal values of sensitive variables inside `kubectl describe` Environment: blocks."""
    if not isinstance(text, str) or not text:
        return text
    out = []
    block_indent = None
    entry_indent = None
    masking = False
    for line in text.split("\n"):
        indent = len(line) - len(line.lstrip())
        header = _ENV_HEADER_RE.match(line)
        if header:
            block_indent, entry_indent, masking = len(header.group(1)), None, False
            out.append(line)
            continue
        if block_indent is None or not line.strip() or indent <= block_indent:
            if line.strip() and block_indent is not None and indent <= block_indent:
                block_indent, entry_indent, masking = None, None, False
            out.append(line)
            continue
        entry = _ENV_ENTRY_RE.match(line)
        if entry and (entry_indent is None or indent <= entry_indent):
            entry_indent = indent
            lead, name, delimiter, value = entry.groups()
            masking = bool(_SENSITIVE_ENV_NAME_RE.search(name)) and not value.startswith("<set to the key")
            out.append(f"{lead}{name}{delimiter}{_MARKER}" if masking and value else line)
            continue
        out.append(" " * indent + _MARKER if masking else line)
    return "\n".join(out)
