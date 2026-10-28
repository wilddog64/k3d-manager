# Investigation verification metrics — Luna and independent review

Operator explicitly requested dispatch to correct recovered incident's misleading
Verified/Live-verified notyet cells. P3spec:
[typed investigation metrics bug](../bugs/2026-10-28-bug-tracking-ignores-investigation-verification.md).
Task investigation-verification-metrics-luna, modelgpt-6-luna, isolated worktree.
Existing CLOSED recovered incident and historicalcause uncertainty remain intact.
No extra table/panel, causal FixSHA, metadata rewrite, deployment/provider/Keychain/
service access or screenshot export. Coordinator independently reviews and lands.

## Independent baseline before implementation

```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/src/gitrepo/personal/k3d-manager
collected 234 items

scripts/tests/bin/test_prior_art.py .................................... [ 15%]
................................................                         [ 35%]
scripts/tests/bin/test_check_bug_evidence.py .......                     [ 38%]
scripts/tests/bin/test_vectordb_bug_metrics.py ......................... [ 49%]
..........ss............................................................ [ 80%]
..............                                                           [ 86%]
scripts/tests/bin/test_live_evidence_acceptance.py ....................  [ 94%]
scripts/tests/bin/test_bug_tally.py ............                         [100%]

======================= 232 passed, 2 skipped in 25.08s ========================
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table separates verified and live-verified status indicators

```
Two optional Plans-query tests skipped because promtool absent from defaultPATH;
final gates will set PROMTOOL to existing3.2.1binary and requirezero skips.

## First draft independent rejection

Actual in-memory publisher/helper probes using task code:
```text
malformed-calendar {"accepted_investigation": false, "fix_sha": "7ea1032f", "live_evidence": "missing", "live_verified": "true", "verified": "true"}
malformed-explicit-fix-header {"accepted_investigation": true, "fix_sha": "-", "live_evidence": "ok", "live_verified": "true", "verified": "true"}

```
Malformed calendar proof incorrectly retainedtrue verification flags because it
fell back to LIVE-VERIFIED status; malformed explicit Fixheader was accepted as
noheader. Typed proof must not bypass explicit causal-fix metadata or promote
invalid proof. Existing unrelated doc_meta assertions had also been removed/
changed; coordinator required restoration, not weaker tests. Requested actual
Git history/ref date/verification-record tests instead of injectedfakeSHA/time,
legacy/unassigned semantics, and marker/header shared consistency.
Luna resumedrun2 with bounded feedback. First draft not committed/landed/accepted.
No new runtime failure or live command is inferred from these offline fixtures.

## Independent final acceptance — PASS

Luna rework2 committedff1c8241 onprivatebranch, rebased/landedc96d0d13 onto current
release. Sharedparser/header/type helpers enforcevalidcalendar/explicitmarker/
noFixheader; malformed explicitFixheaders cannotmasqueradeasabsent. Publisher
failsclosedtypedmissing/invalidproof, preservesnormalcodefix/ancestry/legacy,
suppressesinferredcausalFixSHA, reads exactproofrecordline fromselectedGitref.
Actualsourcebugmetadata unchanged. Coordinator clarified guideverificationtables
and Openfor exception; existing sentence-test retainedcodefixwording and nowalso
assertsexplicitclosedinvestigationproof exception. No newpanel/query/column.

Actual independent final Python output (PROMTOOL3.2.1set, zero skips):
```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/investigation-verification-metrics-luna
collected 269 items

scripts/tests/bin/test_prior_art.py .................................... [ 13%]
.....................................................                    [ 33%]
scripts/tests/bin/test_check_bug_evidence.py ............                [ 37%]
scripts/tests/bin/test_vectordb_bug_metrics.py ......................... [ 46%]
........................................................................ [ 73%]
..............                                                           [ 78%]
scripts/tests/bin/test_live_evidence_acceptance.py ..................... [ 86%]
........................                                                 [ 95%]
scripts/tests/bin/test_bug_tally.py ............                         [100%]

============================= 269 passed in 19.37s =============================

```
Actual independent full BATS:
```text
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table separates verified and live-verified status indicators

```
Ruff on all7touchedPython files:
```text
All checks passed!
```
Python ASTsyntax6filesvalidated; seventh testfile parsed/executedbyfullpytest.
No shell implementation touched: ShellCheck N/A. git diff --check clean.
Actual unchanged incident through new real publisher/Git record path:
```text
{"fix_sha": "-", "live_evidence": "ok", "live_verified": "true", "live_verified_at": "2026-10-28", "status": "fixed", "verified": "true", "verified_at": "2026-10-28", "verified_sha": "7ea1032f"}
PASS: unchanged actual incident metadata; exact proof-record commit; no inferred causal Fix SHA; Open-for stops counting.

```
Independent original-publisher regression (behavioralfailures, not missingAPI):
```text
FFFFFFFFFF..FFFF                                                         [100%]
=================================== FAILURES ===================================
_ test_closed_investigation_publishes_live_proof_without_causal_fix_sha[CLOSED] _

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_closed_investigation_publ0'), '64c571e4045a9bef2233cb85f6e10e03219ab786', '63aa792bc1f290a0bb7958ddafc4719a7aa5140e', '8038dc7ae4b31ac7444914718e620fb0113c8331')
status = 'CLOSED'

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
>       assert 'verified="true"' in row and 'live_verified="true"' in row
E       assert ('verified="true"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="Incident: webhook unresponsive while operator offsite — minimal...verified="false",verified_at="false",live_verified_at="false",fix_sha="abcdef01",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:155: AssertionError
_ test_closed_investigation_publishes_live_proof_without_causal_fix_sha[LIVE-VERIFIED] _

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_closed_investigation_publ1'), '64c571e4045a9bef2233cb85f6e10e03219ab786', '63aa792bc1f290a0bb7958ddafc4719a7aa5140e', '8038dc7ae4b31ac7444914718e620fb0113c8331')
status = 'LIVE-VERIFIED'

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
>       assert 'live_evidence="ok"' in row and 'fix_sha="-"' in row
E       assert ('live_evidence="ok"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="Incident: webhook unresponsive while operator offsite — minimal...-28 12:50Z",live_verified_at="2026-10-28 12:50Z",fix_sha="abcdef01",verified_sha="9bbfe9c1",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:156: AssertionError
___________ test_investigation_publisher_proof_matrix[valid-CLOSED] ____________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p0'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'valid'

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
>           assert 'verified="true"' in row and 'live_verified="true"' in row
E           assert ('verified="true"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:261: AssertionError
________ test_investigation_publisher_proof_matrix[valid-LIVE-VERIFIED] ________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p1'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'LIVE-VERIFIED', kind = 'valid'

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
>           assert 'live_evidence="ok"' in row and row.endswith(" -2")
E           assert ('live_evidence="ok"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="67828789",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:262: AssertionError
__________ test_investigation_publisher_proof_matrix[missing-CLOSED] ___________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p2'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'missing'

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
>           assert 'live_evidence="missing"' in row and not row.endswith(" -2")
E           assert ('live_evidence="missing"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:269: AssertionError
_______ test_investigation_publisher_proof_matrix[missing-LIVE-VERIFIED] _______

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p3'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'LIVE-VERIFIED', kind = 'missing'

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
>           assert 'verified="false"' in row and 'live_verified="false"' in row
E           assert ('verified="false"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="67828789",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:268: AssertionError
_________ test_investigation_publisher_proof_matrix[malformed-CLOSED] __________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p4'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'malformed'

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
>           assert 'live_evidence="missing"' in row and not row.endswith(" -2")
E           assert ('live_evidence="missing"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:269: AssertionError
______ test_investigation_publisher_proof_matrix[malformed-LIVE-VERIFIED] ______

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p5'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'LIVE-VERIFIED', kind = 'malformed'

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
>           assert 'verified="false"' in row and 'live_verified="false"' in row
E           assert ('verified="false"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="67828789",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:268: AssertionError
__________ test_investigation_publisher_proof_matrix[bad-date-CLOSED] __________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p6'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'bad-date'

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
>           assert 'live_evidence="missing"' in row and not row.endswith(" -2")
E           assert ('live_evidence="missing"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:269: AssertionError
______ test_investigation_publisher_proof_matrix[bad-date-LIVE-VERIFIED] _______

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p7'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'LIVE-VERIFIED', kind = 'bad-date'

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
>           assert 'verified="false"' in row and 'live_verified="false"' in row
E           assert ('verified="false"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="67828789",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:268: AssertionError
_______ test_investigation_publisher_proof_matrix[malformed-fix-CLOSED] ________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p10'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'malformed-fix'

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
>           assert 'live_evidence="missing"' in row and not row.endswith(" -2")
E           assert ('live_evidence="missing"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:269: AssertionError
____ test_investigation_publisher_proof_matrix[malformed-fix-LIVE-VERIFIED] ____

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p11'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'LIVE-VERIFIED', kind = 'malformed-fix'

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
>           assert 'verified="false"' in row and 'live_verified="false"' in row
E           assert ('verified="false"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="67828789",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:268: AssertionError
_________ test_investigation_publisher_proof_matrix[valid-fix-CLOSED] __________

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p12'), '14c40c78a2bf4f2852d0e99a40372bdfe3a9e2f9', '67828789640d4d6832553a7b59c59256c376de89', '0a9aa4e623b67b9fd767eab0e3dfb8469204db2a')
status = 'CLOSED', kind = 'valid-fix'

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
>           assert 'live_evidence="missing"' in row and not row.endswith(" -2")
E           assert ('live_evidence="missing"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...verified="false",verified_at="false",live_verified_at="false",fix_sha="67828789",verified_sha="-",live_evidence="-"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:269: AssertionError
______ test_investigation_publisher_proof_matrix[valid-fix-LIVE-VERIFIED] ______

repo = (PosixPath('/private/tmp/pytest-of-cliang/pytest-1950/test_investigation_publisher_p13'), 'decb243430a461ec0806150b773fca846a2789f9', '6b43e543852bb1256349103a58920f6c226ac91a', '4262d57931a9db5cd3b735e6cf43b45ca2f83a3f')
status = 'LIVE-VERIFIED', kind = 'valid-fix'

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
>           assert 'verified="false"' in row and 'live_verified="false"' in row
E           assert ('verified="false"' in 'k3dm_bug_info{repo="k3d-manager",priority="P2",title="provider-confirmed outage cause",filed="2026-10-10",bug="2026-1...ified="true",verified_at="true",live_verified_at="true",fix_sha="6b43e543",verified_sha="-",live_evidence="missing"} 7')

scripts/tests/bin/test_live_evidence_acceptance.py:268: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_closed_investigation_publishes_live_proof_without_causal_fix_sha[CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_closed_investigation_publishes_live_proof_without_causal_fix_sha[LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[valid-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[valid-LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[missing-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[missing-LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[malformed-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[malformed-LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[bad-date-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[bad-date-LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[malformed-fix-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[malformed-fix-LIVE-VERIFIED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[valid-fix-CLOSED]
FAILED scripts/tests/bin/test_live_evidence_acceptance.py::test_investigation_publisher_proof_matrix[valid-fix-LIVE-VERIFIED]
14 failed, 2 passed, 29 deselected in 2.18s

```

## Final-review failure corrected

Coordinator guidewording clarification initially failed an old punctuation-bound
sentenceassertion; implementation269suite otherwise268pass. Actual full output:
```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/investigation-verification-metrics-luna
collected 269 items

scripts/tests/bin/test_prior_art.py .................................... [ 13%]
.....................................................                    [ 33%]
scripts/tests/bin/test_check_bug_evidence.py ............                [ 37%]
scripts/tests/bin/test_vectordb_bug_metrics.py ......................... [ 46%]
....................................................F................... [ 73%]
..............                                                           [ 78%]
scripts/tests/bin/test_live_evidence_acceptance.py ..................... [ 86%]
........................                                                 [ 95%]
scripts/tests/bin/test_bug_tally.py ............                         [100%]

=================================== FAILURES ===================================
____ test_acceptance_M5_grafana_guide_defines_open_for_until_live_verified _____

    def test_acceptance_M5_grafana_guide_defines_open_for_until_live_verified():
        guide = (ROOT / "docs/guides/grafana-dashboards/k3dm-bugs.md").read_text(encoding="utf-8")
>       assert "Open for counts from filed until the bug is LIVE-VERIFIED." in guide
E       assert 'Open for counts from filed until the bug is LIVE-VERIFIED.' in '# k3dm Bug Tracking (`k3dm-bugs`) — hub\n\n[← Grafana dashboards index](../grafana-dashboards.md)\n\nHermes publishes...s release" and "Open in later releases" tiles remain k3d-manager-only\nbecause lib-foundation has no release branch.\n'

scripts/tests/bin/test_vectordb_bug_metrics.py:922: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_vectordb_bug_metrics.py::test_acceptance_M5_grafana_guide_defines_open_for_until_live_verified
======================== 1 failed, 268 passed in 20.78s ========================

```
Extendedexistingassertion toretaincodefixphrase andrequireinvestigationexception.
Stagedauditthenrejectedremovedexactoldassertionline:
```text
WARN: Agent audit: assertions removed from Python test files (add '# agent-audit: allow assert-removed <reason>' on an added line in that file if intended):
WARN: scripts/tests/bin/test_vectordb_bug_metrics.py:
-    assert "Open for counts from filed until the bug is LIVE-VERIFIED." in guide
```
Added supported sourceallowmarker explainingintentionalreplacement, preserving
bothsemanticassertions; no hook/auditbypassflag or budgetchange. Finalaudit output:
```text
INFO: Agent audit: Python assertions removed under an assert-removed allow marker:
INFO: scripts/tests/bin/test_vectordb_bug_metrics.py:
-    assert "Open for counts from filed until the bug is LIVE-VERIFIED." in guide
check-doc-links: 2 file(s) OK
[task/v1.43.9/investigation-verification-metrics-luna ff1c8241] checkpoint: before fix: recognize investigation recovery verification in bug metrics
```
Both staged_agent_lint and_agent_audit exited0. Dispatcherlandingscopein-scope,
rebasedprivatebranchonto1eb33a23, reran269pytest+38BATS+Ruff+diffcheck, allpass,
landedc96d0d13. Nativeverify recordsactualindependentpass; tokensnotinvented.
No fullcurated-suite rerun, prior unrelated failuresremainrecorded. No live
publisher/provider/Keychain/serviceaction or screenshotexport. Firstoperatorstep
bin/k3dm-vectordb-metrics; thenreadpublishedrowandoperatorUIoneatatime. Parent
historicalcause remainsunconfirmed; thisfix verifiestrackingofrecoveryproof only.

## Operator publication and independent live data check — PASS

Operator confirmed publisher completed. Read-only Pushgateway query of exact
incident returned one current row; observation recorded at 2026-10-28T12:57:54.018567+00:00:
```text
k3dm_bug_info{branch="k3d-manager-v1.43.9",bug="2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery",filed="2026-10-26",fix_sha="-",fixed_in="v1.43.9",instance="",job="k3dm-bug-open",live_evidence="ok",live_verified="true",live_verified_at="2026-10-28",priority="P2",release="v1.43.9",release_order="9998.9956.9990 v1.43.9",repo="k3d-manager",sort_key="9998.9956.9990 v1.43.9 P2 3 2026-10-26 2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery",status="fixed",title="Incident: webhook unresponsive while operator offsite — minimal diagnosis and controlled recovery",verified="true",verified_at="2026-10-28",verified_sha="7ea1032f"} -2

```
Assertions passed: statusfixed, verifiedtrue, live_verifiedtrue, live_evidenceok,
dates2026-10-28, actualproofrecordSHA7ea1032f, causalfix_sha'-', value-2 stops
Openforcount. Existing parentmetadata remainedCLOSED/recovered; currentruntime
proof is recognized without claiming a causal fix. Historicalcauseunconfirmed.
DataflowlivePASS; operatorexistingrowvisualcheck stillpending beforefixP3closure.
No coordinatorpublication/service/provider/credentialwrite or screenshotexport.
Docs-onlyverificationrecord; no implementation test rerun required.
