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
