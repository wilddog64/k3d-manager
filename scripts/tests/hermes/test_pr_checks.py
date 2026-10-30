import pytest

from hermes import pr_checks


def test_collect_keeps_newest_check_run_and_uses_repo_paths():
    sha = "1234567890abcdef"
    paths = {}
    paths["/repos/wilddog64/lib-foundation/pulls?state=open&per_page=20"] = [
        {"number": 66, "title": "foundation", "draft": True, "head": {"sha": sha}},
        {"number": 67, "title": "empty", "draft": False, "head": {"sha": "abcdef0123456789"}},
    ]
    paths[f"/repos/wilddog64/lib-foundation/commits/{sha}/check-runs?per_page=100"] = {
        "check_runs": [
            {"id": 10, "name": "lint", "status": "completed", "conclusion": "failure",
             "started_at": "2026-10-16T00:00:00Z", "completed_at": "2026-10-16T00:01:00Z"},
            {"id": 11, "name": "lint", "status": "completed", "conclusion": "success",
             "started_at": "2026-10-16T00:02:00Z", "completed_at": "2026-10-16T00:03:00Z"},
            {"id": 12, "name": "CodeQL", "status": "in_progress", "conclusion": None,
             "started_at": "2026-10-16T00:04:00Z", "completed_at": None},
        ]
    }
    paths["/repos/wilddog64/lib-foundation/commits/abcdef0123456789/check-runs?per_page=100"] = {
        "check_runs": []
    }
    seen = []

    def fetch(path):
        seen.append(path)
        return paths[path]

    prs = pr_checks.collect(fetch, "wilddog64/lib-foundation")
    assert prs[0]["head"] == sha[:8] and prs[0]["draft"] is True
    assert [check["name"] for check in prs[0]["checks"]] == ["lint", "CodeQL"]
    assert prs[0]["checks"][0]["state"] == "success"
    assert prs[0]["checks"][1]["state"] == "in_progress"
    assert prs[0]["checks"][0]["started"] == 1792108920
    assert prs[1]["checks"] == []
    assert all(path.startswith("/repos/wilddog64/lib-foundation/") for path in seen)

    paths[seen[0]] = {}
    try:
        pr_checks.collect(fetch, "wilddog64/lib-foundation")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid pulls response did not fail")


def test_overall_render_and_failure_output():
    assert pr_checks.overall([]) == "none"
    assert pr_checks.overall([{"state": "in_progress"}]) == "running"
    assert pr_checks.overall([{"state": "cancelled"}, {"state": "success"}]) == "success"
    assert pr_checks.overall([{"state": "stale"}, {"state": "success"}]) == "failure"
    prs = [{"number": 66, "title": '"\\\n' + "x" * 150, "head": "12345678", "draft": False,
            "checks": [{"name": "lint", "state": "success", "started": 100, "completed": 160},
                       {"name": "CodeQL", "state": "in_progress", "started": 200, "completed": None},
                       {"name": "queued", "state": "queued", "started": None, "completed": None}]}]
    rendered = pr_checks.render(prs, 250, "wilddog64/k3d-manager")
    assert 'k3dm_pr_info{repo="wilddog64/k3d-manager",pr="66"' in rendered
    assert "k3dm_pr_check_duration_seconds{repo=\"wilddog64/k3d-manager\",pr=\"66\",check=\"lint\"} 60" in rendered
    assert "k3dm_pr_check_completed_timestamp_seconds{repo=\"wilddog64/k3d-manager\",pr=\"66\",check=\"lint\"} 160" in rendered
    assert "check=\"CodeQL\"} 50" in rendered
    assert "completed_timestamp_seconds{repo=\"wilddog64/k3d-manager\",pr=\"66\",check=\"CodeQL\"}" not in rendered
    assert "id=\"" not in rendered
    later_poll = pr_checks.render(prs, 300, "wilddog64/k3d-manager")
    completed = next(line for line in rendered.splitlines() if "completed_timestamp_seconds" in line)
    assert completed in later_poll.splitlines()
    assert "check=\"CodeQL\"} 100" in later_poll
    title = next(line for line in rendered.splitlines() if line.startswith("k3dm_pr_info"))
    title_value = title.split('title="', 1)[1].split('"', 1)[0]
    assert len(title_value) == 100 and title_value.endswith("…")
    failure = pr_checks.render_failure(250, "wilddog64/lib-foundation")
    assert "scrape_success" in failure and " 0" in failure
    assert "k3dm_pr_info" not in failure and "last_scrape_timestamp_seconds" in failure


def test_completed_polls_keep_execution_identity_and_close_removes_current_metrics():
    repo = "wilddog64/shopping-cart-payment"
    pulls_path = f"/repos/{repo}/pulls?state=open&per_page=20"
    responses = {
        pulls_path: [{"number": 93, "title": "payment", "head": {"sha": "abcdef"}}],
        f"/repos/{repo}/commits/abcdef/check-runs?per_page=100": {
            "check_runs": [{
                "id": 123, "name": "lint", "status": "completed", "conclusion": "success",
                "started_at": "2026-10-16T00:02:00Z",
                "completed_at": "2026-10-16T00:03:00Z",
            }],
        },
    }
    labels = f'repo="{repo}",pr="93",check="lint"'
    expected_checks = [
        f'k3dm_pr_check_state{{{labels},state="success"}} 1',
        f"k3dm_pr_check_duration_seconds{{{labels}}} 60.0",
        f"k3dm_pr_check_completed_timestamp_seconds{{{labels}}} 1792108980.0",
    ]
    for now in (1792109000, 1792109300, 1792109600):
        rendered = pr_checks.render(pr_checks.collect(responses.__getitem__, repo), now, repo)
        # Exact producer output forbids poll/run IDs or scrape time replacing completed_at.
        assert [line for line in rendered.splitlines()
                if line.startswith("k3dm_pr_check_")] == expected_checks
        assert f'k3dm_pr_checks_last_scrape_timestamp_seconds{{repo="{repo}"}} {now}' in rendered

    # The open-only endpoint no longer returns the PR after it closes or merges.
    responses[pulls_path] = []
    closed = pr_checks.render(pr_checks.collect(responses.__getitem__, repo), 1792109900, repo)
    assert closed.splitlines() == [
        f'k3dm_pr_checks_open_prs{{repo="{repo}"}} 0',
        f'k3dm_pr_checks_last_scrape_timestamp_seconds{{repo="{repo}"}} 1792109900',
        f'k3dm_pr_checks_scrape_success{{repo="{repo}"}} 1',
    ]


def test_no_pr_repo_and_failed_read_emit_distinct_health_without_fabricated_checks():
    repo = "wilddog64/shopping-cart-e2e-tests"
    seen = []

    def no_prs(path):
        seen.append(path)
        return []

    empty = pr_checks.render(pr_checks.collect(no_prs, repo), 300, repo)
    assert seen == [f"/repos/{repo}/pulls?state=open&per_page=20"]
    assert empty.splitlines() == [
        f'k3dm_pr_checks_open_prs{{repo="{repo}"}} 0',
        f'k3dm_pr_checks_last_scrape_timestamp_seconds{{repo="{repo}"}} 300',
        f'k3dm_pr_checks_scrape_success{{repo="{repo}"}} 1',
    ]

    def failed_read(_path):
        raise OSError("GitHub unavailable")

    with pytest.raises(OSError, match="GitHub unavailable"):
        pr_checks.collect(failed_read, repo)
    assert pr_checks.render_failure(600, repo).splitlines() == [
        f'k3dm_pr_checks_last_scrape_timestamp_seconds{{repo="{repo}"}} 600',
        f'k3dm_pr_checks_scrape_success{{repo="{repo}"}} 0',
    ]
