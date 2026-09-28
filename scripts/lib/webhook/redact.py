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
