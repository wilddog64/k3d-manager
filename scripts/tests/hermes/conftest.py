import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
from hermes import e2e_bugs  # noqa: E402


@pytest.fixture(autouse=True)
def _no_live_retrieval(monkeypatch):
    """Every new Hermes bug doc is built through search(). Unstubbed, that reads the embeddings
    key and the Vault root token and calls the embeddings API. Tests that cover prior art
    override this with their own monkeypatch."""
    def unavailable(*_args, **_kwargs):
        raise e2e_bugs.RetrievalUnavailable("retrieval is stubbed out in tests")

    monkeypatch.setattr(e2e_bugs, "search", unavailable)
