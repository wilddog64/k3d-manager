import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from webhook import agent


def test_claude_prompt_is_after_option_terminator(monkeypatch, tmp_path):
    captured = []
    monkeypatch.setattr(agent, "JOB_DIR", tmp_path)
    monkeypatch.setattr(agent, "_fetch_thread_context", lambda _thread_ts: "prior reply")
    monkeypatch.setattr(agent, "_posix_spawn_capture",
                        lambda cmd, *args, **kwargs: captured.append(cmd) or ("ok", False))
    monkeypatch.setattr(agent, "_notify_job", lambda *args: None)
    monkeypatch.setattr(agent, "_slack_post", lambda *args: None)

    cases = [
        ("plain question", None),
        ("file an issue about the broken thing", None),
        ("follow up question", "THREAD"),
    ]
    for index, (question, thread_ts) in enumerate(cases):
        (tmp_path / str(index)).mkdir()
        agent._run_cluster_ask(str(index), "claude", question, "", thread_ts=thread_ts, max_turns=1)

    assert len(captured) == len(cases)
    for cmd in captured:
        assert cmd[-2] == "--"
        assert "---USER QUESTION START---" in cmd[-1]
        assert cmd[-1] not in cmd[:-2]


def test_parse_observations_strips_cli_preamble_before_answer():
    raw = "Permission allow rule: warning\nANSWER:\nhello"

    answer, filed = agent._parse_gemini_observations(raw)

    assert answer == "hello"
    assert filed == []
    assert "Permission allow rule" not in answer


def test_parse_observations_keeps_observations_after_preamble(monkeypatch, tmp_path):
    monkeypatch.setattr(agent, "REPO_ROOT", tmp_path)
    (tmp_path / "docs" / "bugs").mkdir(parents=True)
    raw = (
        "Permission allow rule: warning\n"
        "ANSWER:\nhello\n\n"
        "OBSERVATIONS:\n- TITLE: t | BODY: b"
    )

    answer, filed = agent._parse_gemini_observations(raw)

    assert answer == "hello"
    assert len(filed) == 1
    assert filed[0].endswith("-t.md")


def test_parse_observations_without_answer_marker_returns_raw_unchanged():
    raw = "Permission allow rule: warning\nhello"

    answer, filed = agent._parse_gemini_observations(raw)

    assert answer == raw
    assert filed == []


def test_parse_observations_ignores_mid_sentence_answer_marker():
    raw = "The answer: ANSWER:\nhello"

    answer, filed = agent._parse_gemini_observations(raw)

    assert answer == raw
    assert filed == []
