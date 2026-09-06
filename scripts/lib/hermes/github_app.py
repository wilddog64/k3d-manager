"""GitHub App installation-token helper using only the Python standard library."""

import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.request
from datetime import datetime, timezone

_CACHE = {}


def _b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _openssl_sign(signing_input, private_key):
    """Return an RS256 signature without putting the key on an argv list."""
    descriptor, keyfile = tempfile.mkstemp(mode=0o600)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(private_key)
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", keyfile],
            input=signing_input.encode(), capture_output=True, check=True,
        )
        return result.stdout
    finally:
        try:
            os.unlink(keyfile)
        except FileNotFoundError:
            pass


def _http_post(url, data, headers):
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read())


def _expiry_epoch(expires_at):
    return int(datetime.fromisoformat(expires_at.replace("Z", "+00:00")).replace(
        tzinfo=timezone.utc).timestamp())


def installation_token(app_id, installation_id, private_key, *, signer=_openssl_sign,
                       http=_http_post, now=None, _cache=_CACHE):
    """Mint or return a cached GitHub App installation token."""
    current = int(time.time()) if now is None else int(now)
    cached = _cache.get(installation_id)
    if cached and current < _expiry_epoch(cached["expires_at"]) - 300:
        return cached["token"]

    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(json.dumps({"iat": current - 60, "exp": current + 540, "iss": app_id},
                                 separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}"
    jwt = f"{signing_input}.{_b64url(signer(signing_input, private_key))}"
    minted = http(
        f"https://api.github.com/app/installations/{installation_id}/access_tokens", b"",
        {"Authorization": f"Bearer {jwt}", "Accept": "application/vnd.github+json",
         "X-GitHub-Api-Version": "2022-11-28"},
    )
    _cache[installation_id] = {"token": minted["token"], "expires_at": minted["expires_at"]}
    return minted["token"]
