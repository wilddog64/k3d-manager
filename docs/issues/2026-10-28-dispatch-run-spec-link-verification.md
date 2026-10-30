# Per-run task-name GitHub404 verification

The operator clicked the task-name link, which guessed a nonexistent plans filename.
The actual start record points to docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md.
This is separate from the Log route; accepted run3 Log navigation already passed.
Fix uses recorded start spec, inherited by resumes, with a safe release-branch fallback.
No layout, Log action, panel count, ledger or global cost/verification policy change.
No screenshot copied or exported. No live publication performed.

Remote document check (gh api contents with release ref):
```json
{"path":"docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md","sha":"85177910bc8bd841373325b3dde227449a95c47a","type":"file"}
```

## Regression before fix

```text
FFFFFFFFFFFF                                                             [100%]
=================================== FAILURES ===================================
________ test_run_spec_link_uses_recorded_issue_instead_of_custom_slug _________

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_uses_record0')

    def test_run_spec_link_uses_recorded_issue_instead_of_custom_slug(tmp_path):
        output = dispatch_metrics.render([
            event(1, "start", "vectordb-retrieval-key-cache", version="v1.43.9", run=1,
                  spec="docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md"),
            event(2, "codex_exit", "vectordb-retrieval-key-cache", version="v1.43.9", run=1, exit=127),
            event(3, "resume", "vectordb-retrieval-key-cache", version="v1.43.9", run=2),
            event(4, "codex_exit", "vectordb-retrieval-key-cache", version="v1.43.9", run=2, exit=0),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
        expected = ('spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/'
                    'docs/issues/2026-10-26-v1439-retrieval-dashboard-no-data.md"')
>       assert len(lines) > 1 and all(expected in line for line in lines)
E       assert (8 > 1 and False)
E        +  where 8 = len(['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="vectordb-retrieval-key-cache",run="1",repo="k3d-m...-cache",run="2",repo="k3d-manager",outcome="unknown",evidence="none",evidence_summary="none",evidence_path=""} 1', ...])
E        +  and   False = all(<generator object test_run_spec_link_uses_recorded_issue_instead_of_custom_slug.<locals>.<genexpr> at 0x1069d7060>)

scripts/tests/bin/test_dispatch_metrics.py:2191: AssertionError
_____ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[None] ______

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_0')
spec = None

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x105654820>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_______ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[9] _______

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_1')
spec = 9

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x105655540>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_______ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[] ________

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_2')
spec = ''

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x108071700>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[../private.md] _

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_3')
spec = '../private.md'

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x108073680>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/../private.md] _

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_4')
spec = 'docs/issues/../private.md'

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x1069b9700>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/unsafe".md] _

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_5')
spec = 'docs/issues/unsafe".md'

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x1069b99a0>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/unsafe\n.md] _

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_6')
spec = 'docs/issues/unsafe\n.md'

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x1069b9ee0>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_ test_run_spec_link_missing_or_unsafe_path_uses_release_branch[/tmp/spec.md] __

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_missing_or_7')
spec = '/tmp/spec.md'

    @pytest.mark.parametrize("spec", [None, 9, "", "../private.md", "docs/issues/../private.md",
                                      'docs/issues/unsafe".md', "docs/issues/unsafe\n.md", "/tmp/spec.md"])
    def test_run_spec_link_missing_or_unsafe_path_uses_release_branch(tmp_path, spec):
        output = dispatch_metrics.render([
            event(1, "start", "unrelated-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "unrelated-slug", version="v1.43.9", run=1, exit=127),
        ], 0, 100, repo_root=tmp_path)
        lines = [line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{")]
>       assert lines and all('spec_url="https://github.com/wilddog64/k3d-manager/tree/k3d-manager-v1.43.9"'
                             in line for line in lines)
E       assert (['k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="unrelated-slug",run="1",repo="k3d-manager",outcom...t.exit",evidence_summary="exit 127; local only (not shipped)",evidence_path="v1.43.9/unrelated-slug.run/codex.log"} 1'] and False)
E        +  where False = all(<generator object test_run_spec_link_missing_or_unsafe_path_uses_release_branch.<locals>.<genexpr> at 0x1069ba7a0>)

scripts/tests/bin/test_dispatch_metrics.py:2204: AssertionError
_____________ test_run_spec_link_accepts_recorded_doc_kinds[plans] _____________

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_accepts_rec0')
directory = 'plans'

    @pytest.mark.parametrize("directory", ["plans", "bugs", "issues"])
    def test_run_spec_link_accepts_recorded_doc_kinds(tmp_path, directory):
        spec = f"docs/{directory}/different-from-slug.md"
        output = dispatch_metrics.render([
            event(1, "start", "custom-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "custom-slug", version="v1.43.9", run=1, exit=0),
        ], 0, 100, repo_root=tmp_path)
        line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
>       assert f'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/{spec}"' in line
E       assert 'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/docs/plans/different-from-slug.md"' in 'k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="custom-slug",run="1",repo="k3d-manager",outcome="unknown",evidence="none",evidence_summary="none",evidence_path=""} 1'

scripts/tests/bin/test_dispatch_metrics.py:2216: AssertionError
_____________ test_run_spec_link_accepts_recorded_doc_kinds[bugs] ______________

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_accepts_rec1')
directory = 'bugs'

    @pytest.mark.parametrize("directory", ["plans", "bugs", "issues"])
    def test_run_spec_link_accepts_recorded_doc_kinds(tmp_path, directory):
        spec = f"docs/{directory}/different-from-slug.md"
        output = dispatch_metrics.render([
            event(1, "start", "custom-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "custom-slug", version="v1.43.9", run=1, exit=0),
        ], 0, 100, repo_root=tmp_path)
        line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
>       assert f'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/{spec}"' in line
E       assert 'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/docs/bugs/different-from-slug.md"' in 'k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="custom-slug",run="1",repo="k3d-manager",outcome="unknown",evidence="none",evidence_summary="none",evidence_path=""} 1'

scripts/tests/bin/test_dispatch_metrics.py:2216: AssertionError
____________ test_run_spec_link_accepts_recorded_doc_kinds[issues] _____________

tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1926/test_run_spec_link_accepts_rec2')
directory = 'issues'

    @pytest.mark.parametrize("directory", ["plans", "bugs", "issues"])
    def test_run_spec_link_accepts_recorded_doc_kinds(tmp_path, directory):
        spec = f"docs/{directory}/different-from-slug.md"
        output = dispatch_metrics.render([
            event(1, "start", "custom-slug", version="v1.43.9", run=1, spec=spec),
            event(2, "codex_exit", "custom-slug", version="v1.43.9", run=1, exit=0),
        ], 0, 100, repo_root=tmp_path)
        line = next(line for line in output.splitlines() if line.startswith("k3dm_dispatch_task_run_outcome{"))
>       assert f'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/{spec}"' in line
E       assert 'spec_url="https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.9/docs/issues/different-from-slug.md"' in 'k3dm_dispatch_task_run_outcome{window="1d",version="v1.43.9",slug="custom-slug",run="1",repo="k3d-manager",outcome="unknown",evidence="none",evidence_summary="none",evidence_path=""} 1'

scripts/tests/bin/test_dispatch_metrics.py:2216: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_uses_recorded_issue_instead_of_custom_slug
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[None]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[9]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[../private.md]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/../private.md]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/unsafe".md]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[docs/issues/unsafe\n.md]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_missing_or_unsafe_path_uses_release_branch[/tmp/spec.md]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_accepts_recorded_doc_kinds[plans]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_accepts_recorded_doc_kinds[bugs]
FAILED scripts/tests/bin/test_dispatch_metrics.py::test_run_spec_link_accepts_recorded_doc_kinds[issues]
12 failed, 139 deselected in 1.88s

```

## Full focused validation

```text
........................................................................ [ 47%]
........................................................................ [ 95%]
.......                                                                  [100%]
151 passed in 13.17s
1..30
ok 1 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 2 agent dispatch dashboard: every queried metric is exported
ok 3 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 4 agent dispatch dashboard: landing success aggregates both sides
ok 5 agent dispatch dashboard: panel rectangles do not overlap
ok 6 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 7 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 8 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 9 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 10 agent dispatch dashboard: rework rate stat reads the selected window
ok 11 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 12 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 13 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 14 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 15 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 16 agent dashboards: all dashboards have the tag-based Agents link
ok 17 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 18 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 19 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 20 agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs
ok 21 agent dispatch: per spec shows which agent landed each spec
ok 22 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 23 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 24 agent cost: daily Claude tokens and cost panels split by kind
ok 25 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 26 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 27 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 28 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
ok 29 agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit
ok 30 agent dispatch: unrecorded attribution is labeled without overwriting known identities
All checks passed!
Checking /private/tmp/k3dm-run-spec-link-rules.yaml
  SUCCESS: 2 rules found
```

Ruff covered both touched Python files; embedded YAML/JSON parsed; promtool checked
both changed queries. ShellCheck does not apply: no shell implementation touched.
Initial Ruff found an unnecessary f-string prefix; removed and recheck clean.
Curated full-repository suite was not rerun for this focused change; previously
recorded unrelated failures remain. Operator must publish metrics before applying
the updated dashboard, then reload and click the reported task-name link. Failed
startup Log local-only view remains a separate pending operator check.

## Required gates and commit

```text
$ ./scripts/k3d-manager _agent_lint
running under bash version 5.3.20(1)-release
$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.20(1)-release
```
Both exited 0 on staged changes. No shell implementation touched; ShellCheck not applicable.
Correction commit fbb52f67, with checkpoint hooks passing:
```text
check-doc-links: 4 file(s) OK
[k3d-manager-v1.43.9 fbb52f67] checkpoint: before fix: link dispatch runs to their recorded spec
```

## Operator publication and live click — PASS

Operator confirmed make dispatch-metrics completed. Actual supplied apply output:
```text
Warning: resource configmaps/grafana-dashboard-agent-dispatch is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/grafana-dashboard-agent-dispatch configured
```
Annotation warning automatically handled by kubectl; apply succeeded.
Following full-reload/click instructions, operator screenshot shows GitHub path
k3d-manager / docs / issues / 2026-10-26-v1439-retrieval-dashboard-no-data.md,
rendered Preview and title “VectorDB retrieval dashboard stays empty during probe.”
Expected recorded document opens without a 404: task-name navigation PASS.
The document's underlying retrieval issue status is not changed by this check.
No new failure, screenshot export, live coordinator mutation or code change.
Documentation only: implementation tests not rerun; prior 151 pytest/30 BATS,
Ruff and PromQL results above remain applicable. No shell implementation touched.

Recording checkpoint initially rejected missing explicit Fix commit metadata:
```text
docs/bugs/2026-10-28-dispatch-run-spec-link-guesses-filename.md: LIVE-VERIFIED needs a **Fix commit:** <sha> line naming the commit that fixed it
ERROR: Checkpoint commit failed; resolve git errors and retry
```
Added Fix commit fbb52f67; retried normal hooks without bypass.
