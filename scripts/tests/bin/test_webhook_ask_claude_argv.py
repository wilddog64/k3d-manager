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
