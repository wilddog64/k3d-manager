import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.github_app import installation_token


def _decode(segment):
    return json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))


def test_installation_token_builds_expected_jwt_and_mints_for_installation():
    calls = []

    def signer(signing_input, private_key):
        calls.append((signing_input, private_key))
        return b"signature"

    def http(url, data, headers):
        calls.append((url, data, headers))
        return {"token": "minted", "expires_at": "2026-09-06T13:00:00Z"}

    token = installation_token("123", "456", "private-key", signer=signer, http=http,
                               now=1_788_696_000, _cache={})

    header, payload = calls[0][0].split(".")
    assert _decode(header) == {"alg": "RS256", "typ": "JWT"}
    assert _decode(payload) == {"iat": 1_788_695_940, "exp": 1_788_696_540, "iss": "123"}
    assert calls[1][0].endswith("/app/installations/456/access_tokens")
    assert calls[1][1] == b""
    assert token == "minted"


def test_installation_token_caches_until_five_minutes_before_expiry():
    calls = []

    def http(*_args):
        calls.append(True)
        return {"token": f"minted-{len(calls)}", "expires_at": "2026-09-06T13:00:00Z"}

    cache = {}
    assert installation_token("1", "install", "key", signer=lambda *_: b"sig", http=http,
                              now=1_788_695_000, _cache=cache) == "minted-1"
    assert installation_token("1", "install", "key", signer=lambda *_: b"sig", http=http,
                              now=1_788_697_000, _cache=cache) == "minted-1"
    assert installation_token("1", "install", "key", signer=lambda *_: b"sig", http=http,
                              now=1_788_699_400, _cache=cache) == "minted-2"
    assert len(calls) == 2
