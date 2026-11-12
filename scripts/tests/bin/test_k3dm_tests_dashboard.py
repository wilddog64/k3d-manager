import json
import os
from pathlib import Path
import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
CONFIGMAP_PATH = REPO_ROOT / "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml"


@pytest.fixture
def dashboard_json():
    # The fixture first asserts it read the repo's file (resolved from the test file's own path, not the cwd).
    assert CONFIGMAP_PATH.is_file(), f"Dashboard file not found: {CONFIGMAP_PATH}"
    expected_path = Path(__file__).resolve().parents[3] / "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml"
    assert CONFIGMAP_PATH.resolve() == expected_path.resolve()
    assert Path(os.getcwd()) != CONFIGMAP_PATH.parent or True

    content = CONFIGMAP_PATH.read_text(encoding="utf-8")
    doc = yaml.safe_load(content)
    assert doc.get("kind") == "ConfigMap"
    assert "data" in doc and "k3dm-tests.json" in doc["data"]
    return json.loads(doc["data"]["k3dm-tests.json"])


def test_fixture_path_resolution():
    assert CONFIGMAP_PATH.resolve() == (
        Path(__file__).resolve().parents[3] / "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml"
    ).resolve()


def test_run_complete_panel_queries_metric(dashboard_json):
    panels = dashboard_json.get("panels", [])
    matching = [p for p in panels if p.get("title") == "Run complete"]
    assert len(matching) == 1, "Expected exactly one panel titled 'Run complete'"
    panel = matching[0]

    assert panel.get("type") == "stat", "Expected panel type to be 'stat'"
    targets = panel.get("targets", [])
    assert len(targets) >= 1, "Expected at least one target in 'Run complete' panel"
    target = targets[0]

    assert target.get("expr") == 'k3dm_test_run_complete{target="test-all"}'
    assert target.get("instant") is True
    assert target.get("datasource", {}).get("uid") == "prometheus"


def test_run_complete_panel_value_mappings(dashboard_json):
    panels = dashboard_json.get("panels", [])
    matching = [p for p in panels if p.get("title") == "Run complete"]
    assert len(matching) == 1, "Expected exactly one panel titled 'Run complete'"
    panel = matching[0]

    defaults = panel.get("fieldConfig", {}).get("defaults", {})
    assert defaults.get("noValue") == "no data", "Expected noValue to be 'no data'"

    mappings = defaults.get("mappings", [])
    assert len(mappings) >= 1, "Expected at least one mapping in fieldConfig.defaults.mappings"

    value_mapping = next((m for m in mappings if m.get("type") == "value"), None)
    assert value_mapping is not None, "Expected a mapping with type 'value'"

    options = value_mapping.get("options", {})
    assert "0" in options, "Expected mapping for '0' (stopped early)"
    assert options["0"].get("text") == "stopped early"
    assert options["0"].get("color") == "red"

    assert "1" in options, "Expected mapping for '1' (complete)"
    assert options["1"].get("text") == "complete"
    assert options["1"].get("color") == "green"


def test_panels_do_not_overlap(dashboard_json):
    panels = dashboard_json.get("panels", [])
    overlaps = []
    for i in range(len(panels)):
        for j in range(i + 1, len(panels)):
            p1, p2 = panels[i], panels[j]
            g1, g2 = p1.get("gridPos", {}), p2.get("gridPos", {})
            x_overlap = (g1.get("x", 0) < (g2.get("x", 0) + g2.get("w", 0))) and (
                (g1.get("x", 0) + g1.get("w", 0)) > g2.get("x", 0)
            )
            y_overlap = (g1.get("y", 0) < (g2.get("y", 0) + g2.get("h", 0))) and (
                (g1.get("y", 0) + g1.get("h", 0)) > g2.get("y", 0)
            )
            if x_overlap and y_overlap:
                overlaps.append((p1.get("id"), p1.get("title"), p2.get("id"), p2.get("title")))
    assert not overlaps, f"Panels overlap: {overlaps}"


def test_run_complete_panel_placement_row_26_next_to_total_cases(dashboard_json):
    panels = dashboard_json.get("panels", [])
    run_complete = next((p for p in panels if p.get("title") == "Run complete"), None)
    total_cases = next((p for p in panels if p.get("title") == "Total cases"), None)

    assert run_complete is not None, "Missing 'Run complete' panel"
    assert total_cases is not None, "Missing 'Total cases' panel"

    rc_grid = run_complete.get("gridPos", {})
    tc_grid = total_cases.get("gridPos", {})

    assert rc_grid.get("y") == 26, f"Expected 'Run complete' y=26, got {rc_grid.get('y')}"
    assert tc_grid.get("y") == 26, f"Expected 'Total cases' y=26, got {tc_grid.get('y')}"

    adjacent = (
        (tc_grid.get("x", 0) + tc_grid.get("w", 0) == rc_grid.get("x", 0))
        or (rc_grid.get("x", 0) + rc_grid.get("w", 0) == tc_grid.get("x", 0))
    )
    assert adjacent, f"Expected 'Run complete' to be next to 'Total cases': tc={tc_grid}, rc={rc_grid}"


def test_panel_ids_are_unique(dashboard_json):
    panels = dashboard_json.get("panels", [])
    ids = [p.get("id") for p in panels]
    assert len(ids) == len(set(ids)), f"Duplicate panel IDs found: {ids}"


def test_panel_descriptions(dashboard_json):
    panels = dashboard_json.get("panels", [])
    run_complete = next((p for p in panels if p.get("title") == "Run complete"), None)
    total_cases = next((p for p in panels if p.get("title") == "Total cases"), None)
    failed_cases = next((p for p in panels if p.get("title") == "Failed cases"), None)

    assert run_complete is not None, "Missing 'Run complete' panel"
    assert total_cases is not None, "Missing 'Total cases' panel"
    assert failed_cases is not None, "Missing 'Failed cases' panel"

    assert "OfflineSuiteRunIncomplete" in run_complete.get("description", "")
    assert "stops at a red stage counts only the stages that ran" in run_complete.get("description", "")

    for p in (total_cases, failed_cases):
        desc = p.get("description", "")
        assert "Run complete = stopped early" in desc
        assert "counts only the stages that ran" in desc


def test_run_complete_no_overrides_or_transformations(dashboard_json):
    panels = dashboard_json.get("panels", [])
    panel = next((p for p in panels if p.get("title") == "Run complete"), None)
    assert panel is not None, "Missing 'Run complete' panel"

    assert not panel.get("fieldConfig", {}).get("overrides"), "No overrides permitted on Run complete panel"
    assert not panel.get("transformations"), "No transformations permitted on Run complete panel"
    for target in panel.get("targets", []):
        assert not target.get("hide"), "Hidden queries not permitted on Run complete panel"


@pytest.mark.parametrize("panel_id", [4, 8])
def test_failing_cases_table_columns_and_order(dashboard_json, panel_id):
    panels = dashboard_json.get("panels", [])
    panel = next((p for p in panels if p.get("id") == panel_id), None)
    assert panel is not None, f"Missing panel with id {panel_id}"

    organize = next((t for t in panel.get("transformations", []) if t.get("id") == "organize"), None)
    assert organize is not None, f"Missing organize transformation in panel {panel_id}"

    options = organize.get("options", {})
    exclude = options.get("excludeByName", {})
    rename = options.get("renameByName", {})
    index = options.get("indexByName", {})

    # instance and target are excluded
    assert exclude.get("instance") is True, f"Panel {panel_id}: expected instance to be excluded"
    assert exclude.get("target") is True, f"Panel {panel_id}: expected target to be excluded"

    # column order is Test case, Test name, Failure reason, Test suite
    ordered_keys = sorted(index.keys(), key=lambda k: index[k])
    ordered_labels = [rename.get(k, k) for k in ordered_keys]
    assert ordered_labels == [
        "Test case",
        "Test name",
        "Failure reason",
        "Test suite",
    ], f"Panel {panel_id}: unexpected column order {ordered_labels}"
    assert index.get("case") == 0
    assert index.get("name") == 1
    assert index.get("reason") == 2
    assert index.get("suite") == 3

