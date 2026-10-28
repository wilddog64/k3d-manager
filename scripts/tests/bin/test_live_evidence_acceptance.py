import importlib.machinery, importlib.util, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
import pytest

REPO = Path(__file__).resolve().parents[3]
MODULE = os.environ.get("LE_MODULE", str(REPO / "bin" / "k3dm-vectordb-metrics"))
NOW = datetime(2026, 10, 17, 12, 0, tzinfo=timezone.utc)

def _load():
    l = importlib.machinery.SourceFileLoader("le_mod", MODULE)
    s = importlib.util.spec_from_loader("le_mod", l); m = importlib.util.module_from_spec(s); l.exec_module(m); return m

def _git(repo, *a):
    return subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, text=True).stdout.strip()

@pytest.fixture
def repo(tmp_path):
    _git(tmp_path.parent, "init", "-q", str(tmp_path))
    _git(tmp_path, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "old")
    old = _git(tmp_path, "rev-parse", "HEAD")
    _git(tmp_path, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "fix")
    fix = _git(tmp_path, "rev-parse", "HEAD")
    _git(tmp_path, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "later")
    later = _git(tmp_path, "rev-parse", "HEAD")
    return tmp_path, old, fix, later

def _doc(evidence_lines):
    return "\n".join(["# Bug: x", "", "**Status:** LIVE-VERIFIED — 2026-10-17", "**Priority:** P3",
                      "**Filed:** 2026-10-10", *evidence_lines]) + "\n"

def _ev(commit, sep=" · "):
    return sep.join(["**Live evidence:** 2026-10-17", "run r1", "env sandbox/m4", "scenario s/x", f"commit {commit}", "proves E3"])

def _row(repo_path, text, fixed_in, release="v1.43.4"):
    m = _load(); path = "docs/bugs/2026-10-10-x.md"
    tally = {release: {"open_paths": [], "unknown_paths": [], "closed_paths": [{"path": path}]}}
    out = m._bug_status_metrics(repo_path, now=NOW, tally=tally, texts={path: text}, fixed_in=fixed_in, verification_times={})
    rows = [l for l in out.splitlines() if l.startswith("k3dm_bug_info{")]
    assert len(rows) == 1; return rows[0]

def test_N1_old_evidence_is_stale_and_keeps_counting(repo):
    r, old, fix, _ = repo
    row = _row(r, _doc([_ev(old[:8])]), {"docs/bugs/2026-10-10-x.md": {"commit": fix, "release": "v1.43.4"}})
    assert 'live_evidence="stale"' in row
    assert row.endswith(" 7")

def test_M2_evidence_after_fix_is_ok(repo):
    r, _, fix, later = repo
    row = _row(r, _doc([_ev(later[:10], " | ")]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="ok"' in row and row.endswith(" -2")

def test_M3_no_evidence_missing(repo):
    r, _, fix, _ = repo
    row = _row(r, _doc([]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="missing"' in row and row.endswith(" 7")

def test_N3_malformed_line_is_not_evidence(repo):
    r, _, fix, later = repo
    bad = _ev(later).replace("commit ", "commit Z")
    row = _row(r, _doc([bad, _ev(later).replace(" · proves E3", "")]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="missing"' in row

def test_M5_old_release_na(repo):
    r, old, fix, _ = repo
    row = _row(r, _doc([]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}}, release="v1.43.3")
    assert 'live_evidence="n/a"' in row and row.endswith(" -2")

def test_M5_unknown_fix_commit_with_evidence_is_unchecked(repo):
    r, _, _, later = repo
    row = _row(r, _doc([_ev(later)]), {})
    assert 'live_evidence="unchecked"' in row

def test_M3_unknown_fix_commit_without_evidence_is_missing(repo):
    r, _, _, _ = repo
    row = _row(r, _doc([]), {})
    assert 'live_evidence="missing"' in row

def _lint(repo_path, rel, text, head_text=None):
    p = repo_path / rel; p.parent.mkdir(parents=True, exist_ok=True)
    if head_text is not None:
        p.write_text(head_text); _git(repo_path, "add", rel)
        _git(repo_path, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "-m", "h")
    p.write_text(text)
    return subprocess.run([sys.executable, str(REPO / "scripts/check-bug-evidence.py"), rel], cwd=repo_path, capture_output=True, text=True)

def test_M6_flip_without_evidence_fails(repo):
    r, *_ = repo
    res = _lint(r, "docs/bugs/2026-10-10-x.md", _doc([]), head_text=_doc([]).replace("LIVE-VERIFIED — 2026-10-17", "FIXED"))
    assert res.returncode == 1 and "2026-10-10-x.md" in res.stderr

def test_M6_flip_with_evidence_passes(repo):
    r, _, fix, later = repo
    res = _lint(r, "docs/bugs/2026-10-10-x.md", _doc([f"**Fix commit:** `{fix}`", _ev(later)]), head_text=_doc([]).replace("LIVE-VERIFIED — 2026-10-17", "FIXED"))
    assert res.returncode == 0, res.stderr

def test_M6_new_file_live_without_evidence_fails(repo):
    r, *_ = repo
    assert _lint(r, "docs/bugs/2026-10-11-y.md", _doc([])).returncode == 1

def _investigation_doc(verification_type="investigation", evidence=None):
    line = evidence or (
        "**Live investigation evidence:** 2026-10-20 · source hostinger-support · "
        "reference hpanel-response-2026-10-20 · env hostinger/srv1754834 · "
        "scenario emergency-security-patch-restart · proves shutdown-cause"
    )
    return "\n".join([
        "# Bug: provider-confirmed outage cause",
        "",
        "**Status:** LIVE-VERIFIED — provider confirmed the cause",
        "**Priority:** P2",
        f"**Verification type:** {verification_type}",
        line,
        "",
    ])

def test_investigation_live_evidence_passes_without_fix_commit(repo):
    r, *_ = repo
    res = _lint(r, "docs/bugs/2026-10-11-investigation.md", _investigation_doc())
    assert res.returncode == 0, res.stderr

@pytest.mark.parametrize("status", ["CLOSED", "LIVE-VERIFIED"])
def test_closed_investigation_publishes_live_proof_without_causal_fix_sha(repo, status):
    r, *_ = repo
    text = (REPO / "docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md").read_text()
    text = "\n".join(
        "**Status:** " + status + " — operationally recovered" if line.startswith("**Status:") else line
        for line in text.splitlines()
    ) + "\n"
    path = "docs/bugs/2026-10-10-x.md"
    doc_path = r / path
    doc_path.parent.mkdir(parents=True, exist_ok=True)
    doc_path.write_text(text.replace("2026-10-28", "2026-10-27"))
    _git(r, "add", path)
    _git(r, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "-m", "earlier investigation proof")
    doc_path.write_text(text)
    _git(r, "add", path)
    _git(r, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "-m", "record investigation proof")
    record_sha = _git(r, "rev-parse", "HEAD")
    metrics = _load()
    # Later working tree and HEAD changes must not affect the scanned historical ref.
    doc_path.write_text(text.replace("2026-10-28", "2026-10-29"))
    _git(r, "add", path)
    _git(r, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "-m", "later investigation proof")
    historical_texts = metrics._bug_texts(r, record_sha)
    assert historical_texts[path] == text
    verification_times = metrics._verification_times(r, record_sha, historical_texts)
    tally = {"v1.43.9": {"open_paths": [], "unknown_paths": [], "closed_paths": [{"path": path}]}}
    output = metrics._bug_status_metrics(
        r, ref=record_sha, now=NOW, tally=tally, texts=historical_texts,
        fixed_in={path: {"commit": "abcdef0123456789", "release": "v1.43.9"}},
        verification_times=verification_times,
    )
    row = next(line for line in output.splitlines() if line.startswith("k3dm_bug_info{"))
    assert 'verified="true"' in row and 'live_verified="true"' in row
    assert 'live_evidence="ok"' in row and 'fix_sha="-"' in row
    assert f'verified_sha="{record_sha[:8]}"' in row
    assert 'verified_at="2026-10-28"' in row and 'live_verified_at="2026-10-28"' in row
    assert row.endswith(" -2")

def test_open_investigation_does_not_publish_verification(repo):
    r, *_ = repo
    text = _investigation_doc().replace("LIVE-VERIFIED — provider confirmed the cause", "OPEN — investigating")
    row = _row(r, text, {})
    assert 'status="open"' in row and 'verified="-"' in row and 'live_verified="-"' in row

def test_old_release_investigation_keeps_historic_na_values(repo):
    r, *_ = repo
    text = _investigation_doc().replace("LIVE-VERIFIED — provider confirmed the cause", "CLOSED — operationally recovered")
    row = _row(r, text, {}, release="v1.43.1")
    assert 'verified="n/a"' in row and 'live_verified="n/a"' in row
    assert 'live_evidence="n/a"' in row

def test_investigation_evidence_requires_investigation_type(repo):
    r, *_ = repo
    res = _lint(
        r,
        "docs/bugs/2026-10-11-investigation.md",
        _investigation_doc(verification_type="implementation"),
    )
    assert res.returncode == 1
    assert "requires **Verification type:** investigation" in res.stderr

def test_malformed_investigation_evidence_fails(repo):
    r, *_ = repo
    res = _lint(
        r,
        "docs/bugs/2026-10-11-investigation.md",
        _investigation_doc(evidence="**Live investigation evidence:** insufficient detail"),
    )
    assert res.returncode == 1
    assert "typed **Live investigation evidence:** line" in res.stderr

def test_investigation_evidence_cannot_replace_fix_evidence(repo):
    r, _, fix, _ = repo
    text = _investigation_doc().replace(
        "**Priority:** P2", f"**Priority:** P2\n**Fix commit:** `{fix}`"
    )
    res = _lint(r, "docs/bugs/2026-10-11-investigation.md", text)
    assert res.returncode == 1
    assert "only for bugs without a **Fix commit:**" in res.stderr

def test_N2_already_live_at_head_passes(repo):
    r, *_ = repo
    assert _lint(r, "docs/bugs/2026-10-10-x.md", _doc([]) + "edit\n", head_text=_doc([])).returncode == 0

def test_fix_commit_header_overrides_status_proxy(repo):
    r, old, fix, later = repo
    text = _doc([_ev(old[:8])]).replace("**Filed:** 2026-10-10", "**Filed:** 2026-10-10\n**Fix commit:** `" + old[:8] + "`")
    row = _row(r, text, {"docs/bugs/2026-10-10-x.md": {"commit": later}})
    assert 'live_evidence="ok"' in row

def test_proves_fix_token_accepted(repo):
    r, _, fix, later = repo
    row = _row(r, _doc([_ev(later).replace("proves E3", "proves fix")]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="ok"' in row

def test_N4_fix_sha_label_is_per_row(repo):
    r, old, fix, later = repo
    m = _load()
    a, b = "docs/bugs/2026-10-10-a.md", "docs/bugs/2026-10-10-b.md"
    tally = {"v1.43.4": {"open_paths": [], "unknown_paths": [], "closed_paths": [{"path": a}, {"path": b}]}}
    fixed = "**Status:** FIXED\n**Priority:** P3\n**Filed:** 2026-10-10\n"
    out = m._bug_status_metrics(r, now=NOW, tally=tally, texts={a: fixed, b: fixed},
                                fixed_in={a: {"commit": old}, b: {"commit": later}}, verification_times={})
    rows = {l.split('bug="')[1].split('"')[0]: l for l in out.splitlines() if l.startswith("k3dm_bug_info{")}
    assert f'fix_sha="{old[:8]}"' in rows["2026-10-10-a"]
    assert f'fix_sha="{later[:8]}"' in rows["2026-10-10-b"]

def test_N5_unresolvable_commit_is_unchecked_not_stale(repo):
    r, old, fix, later = repo
    gone = "0123456789abcdef0123456789abcdef01234567"
    row = _row(r, _doc([_ev(gone)]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="unchecked"' in row
    row = _row(r, _doc([_ev(later)]), {"docs/bugs/2026-10-10-x.md": {"commit": gone}})
    assert 'live_evidence="unchecked"' in row

def test_N5_resolvable_non_ancestor_stays_stale(repo):
    r, old, fix, later = repo
    row = _row(r, _doc([_ev(old)]), {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    assert 'live_evidence="stale"' in row


@pytest.mark.parametrize("status", ["CLOSED", "LIVE-VERIFIED"])
@pytest.mark.parametrize("kind", ["valid", "missing", "malformed", "bad-date", "no-marker", "malformed-fix", "valid-fix"])
def test_investigation_publisher_proof_matrix(repo, status, kind):
    r, _, fix, _ = repo
    text = _investigation_doc().replace("LIVE-VERIFIED — provider confirmed the cause", status)
    if kind == "missing":
        text = "\n".join(line for line in text.splitlines() if not line.startswith("**Live investigation evidence:"))
    elif kind == "malformed":
        text = text.replace(" · proves shutdown-cause", "")
    elif kind == "bad-date":
        text = text.replace("2026-10-20", "2026-02-30")
    elif kind == "no-marker":
        text = text.replace("**Verification type:** investigation\n", "")
    elif kind in ("malformed-fix", "valid-fix"):
        text += "**Fix commit:** " + (fix if kind == "valid-fix" else "not-a-sha") + "\n"
    row = _row(r, text, {"docs/bugs/2026-10-10-x.md": {"commit": fix}})
    if kind == "valid":
        assert 'verified="true"' in row and 'live_verified="true"' in row
        assert 'live_evidence="ok"' in row and row.endswith(" -2")
    elif kind == "no-marker":
        # An untyped doc retains the established status-based code-fix policy.
        expected = "true" if status == "LIVE-VERIFIED" else "false"
        assert f'verified="{expected}"' in row and 'live_evidence="ok"' not in row
    else:
        assert 'verified="false"' in row and 'live_verified="false"' in row
        assert 'live_evidence="missing"' in row and not row.endswith(" -2")
    expected_fix = fix[:8] if kind in ("valid-fix", "no-marker") else "-"
    assert f'fix_sha="{expected_fix}"' in row


@pytest.mark.parametrize("release", ["v1.43.1", "unassigned", "v1.43.3"])
@pytest.mark.parametrize("valid", [True, False])
def test_investigation_release_policy(repo, release, valid):
    r, *_ = repo
    text = _investigation_doc()
    if not valid:
        text = text.replace(" · proves shutdown-cause", "")
    row = _row(r, text, {}, release=release)
    flags = ("true" if valid else "false") if release == "v1.43.3" else "n/a"
    assert f'verified="{flags}"' in row and f'live_verified="{flags}"' in row
    assert 'live_evidence="n/a"' in row and 'fix_sha="-"' in row


def test_typed_doc_can_use_ordinary_code_fix_proof_and_ancestry(repo):
    r, old, fix, later = repo
    text = _investigation_doc() + f"**Fix commit:** {fix}\n" + _ev(later) + "\n"
    row = _row(r, text, {})
    assert 'live_evidence="ok"' in row and f'fix_sha="{fix[:8]}"' in row
    assert _lint(r, "docs/bugs/ordinary.md", text).returncode == 0
    stale = text.replace(_ev(later), _ev(old))
    assert 'live_evidence="stale"' in _row(r, stale, {})
    assert _lint(r, "docs/bugs/ordinary.md", stale).returncode == 1
