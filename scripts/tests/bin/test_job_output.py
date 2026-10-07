import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook.job_output import read_job_output


def _write(job_dir, name, content):
    (job_dir / name).write_text(content)


def test_make_log_precedes_output_and_log(tmp_path):
    _write(tmp_path, "target", "test")
    _write(tmp_path, "make.log", "make output")
    _write(tmp_path, "output", "old output")
    _write(tmp_path, "log", "old log")

    assert read_job_output(tmp_path) == "make output"


def test_make_job_falls_back_to_output(tmp_path):
    _write(tmp_path, "target", "test")
    _write(tmp_path, "output", "captured output")

    assert read_job_output(tmp_path) == "captured output"


def test_non_make_job_preserves_log_precedence(tmp_path):
    _write(tmp_path, "log", "job log")
    _write(tmp_path, "output", "job output")
    _write(tmp_path, "make.log", "unrelated make log")

    assert read_job_output(tmp_path) == "job log"


def test_missing_or_empty_output_is_empty(tmp_path):
    assert read_job_output(tmp_path) == ""
    _write(tmp_path, "target", "test")
    _write(tmp_path, "make.log", "")
    assert read_job_output(tmp_path) == ""


def test_output_is_bounded_to_tail(tmp_path):
    _write(tmp_path, "target", "test")
    _write(tmp_path, "make.log", "a" * 3000)

    result = read_job_output(tmp_path, max_chars=2000)
    assert len(result) == 2000
    assert result == "a" * 2000


def test_output_is_redacted_before_return(tmp_path):
    _write(tmp_path, "target", "test")
    _write(tmp_path, "make.log", "token=secret-value\nBearer abc123")

    result = read_job_output(tmp_path)
    assert "secret-value" not in result
    assert "abc123" not in result
    assert "***REDACTED***" in result


def test_custom_redactor_is_applied_after_builtin_redaction(tmp_path):
    _write(tmp_path, "target", "test")
    _write(tmp_path, "make.log", "safe output")

    assert read_job_output(tmp_path, redact=lambda text: text.upper()) == "SAFE OUTPUT"
