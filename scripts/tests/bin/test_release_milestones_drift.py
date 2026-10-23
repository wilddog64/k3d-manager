import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def test_release_milestones_stay_in_sync_with_roadmap():
    payload = json.loads((ROOT / "docs/release-milestones.json").read_text())
    versions = [item["version"] for item in payload["milestones"]]
    assert sum(bool(item.get("target")) for item in payload["milestones"]) == 1
    assert versions == sorted(versions, key=lambda v: tuple(map(int, v[1:].split("."))))
    roadmap = (ROOT / "docs/roadmap.md").read_text()
    assert all(version in roadmap for version in versions)
    target = versions[-1]
    tags = set(subprocess.run(["git", "tag", "--list", "v*"], cwd=ROOT,
                              text=True, capture_output=True, check=True).stdout.splitlines())
    headings = re.findall(r"^### Candidate milestone — (v\d+\.\d+\.\d+)", roadmap, re.M)
    limit = tuple(map(int, target[1:].split(".")))
    for version in headings:
        key = tuple(map(int, version[1:].split(".")))
        if version not in tags and key <= limit:
            assert version in versions, version
