"""Exercise Alertmanager notification behaviour with a local fake receiver."""

from __future__ import annotations

import copy
import json
import math
import os
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

import pytest
import yaml


ALERTMANAGER_IMAGE = "quay.io/prometheus/alertmanager:v0.27.0"
REPO_ROOT = Path(__file__).resolve().parents[3]
TEMPLATE = REPO_ROOT / "scripts/etc/prometheus/alertmanager.yaml.tmpl"
pytestmark = pytest.mark.external("runs the pinned Alertmanager image in Docker")


class Sink:
    def __init__(self) -> None:
        self.messages: list[tuple[str, dict]] = []
        self.lock = threading.Lock()

    def add(self, path: str, payload: dict) -> None:
        with self.lock:
            self.messages.append((path, payload))

    def get(self, path: str | None = None) -> list[dict]:
        with self.lock:
            return [payload for message_path, payload in self.messages if path is None or message_path == path]


class Handler(BaseHTTPRequestHandler):
    sink: Sink

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        length = int(self.headers["Content-Length"])
        payload = json.loads(self.rfile.read(length))
        self.sink.add(self.path, payload)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, _format: str, *_args: object) -> None:
        return


def run(*args: str, **kwargs: object) -> subprocess.CompletedProcess[str]:
    kwargs.setdefault("check", True)
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def docker_reason() -> str | None:
    if shutil.which("docker") is None:
        return "Docker CLI is not installed"
    try:
        run("docker", "info", timeout=5)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        return f"Docker daemon is unavailable: {exc}"
    return None


@pytest.fixture(scope="session", autouse=True)
def require_docker() -> None:
    reason = docker_reason()
    if reason:
        pytest.skip(reason)


def render_template(path: Path) -> dict:
    values = {
        "ALERTMANAGER_GMAIL_FROM": "operator@example.invalid",
        "ALERTMANAGER_GMAIL_APP_PW": "dummy-app-password",
        "ALERTMANAGER_SMS_GATEWAY": "sms@example.invalid",
    }
    rendered = run(
        "envsubst",
        "${ALERTMANAGER_GMAIL_FROM} ${ALERTMANAGER_GMAIL_APP_PW} ${ALERTMANAGER_SMS_GATEWAY}",
        input=TEMPLATE.read_text(),
        env={**os.environ, **values},
    ).stdout
    path.write_text(rendered)
    return yaml.safe_load(rendered)


def rewrite_for_test(config: dict, sink_port: int) -> dict:
    original = copy.deepcopy(config)

    def routing_shape(route: dict) -> dict:
        return {
            key: value
            for key, value in route.items()
            if key not in {"group_wait", "group_interval", "repeat_interval", "routes"}
        } | {"routes": [routing_shape(child) for child in route.get("routes", [])]}

    def rewrite_route(route: dict) -> None:
        for key, value in (("group_wait", "1s"), ("group_interval", "2s"), ("repeat_interval", "6s")):
            if key in route:
                route[key] = value
        for child in route.get("routes", []):
            rewrite_route(child)

    rewrite_route(config["route"])
    for receiver in config["receivers"]:
        if "email_configs" in receiver:
            email = receiver.pop("email_configs")
            receiver["webhook_configs"] = [
                {
                    "url": f"http://host.docker.internal:{sink_port}/{receiver['name']}",
                    "send_resolved": email[0].get("send_resolved", False),
                }
            ]

    assert routing_shape(config["route"]) == routing_shape(original["route"])
    assert config["inhibit_rules"] == original["inhibit_rules"]
    return config


@pytest.fixture
def alertmanager(tmp_path: Path):
    sink = Sink()
    Handler.sink = sink
    server = ThreadingHTTPServer(("0.0.0.0", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    config = render_template(tmp_path / "rendered.yaml")
    rewrite_for_test(config, server.server_port)
    config_path = tmp_path / "test-config.yaml"
    config_path.write_text(yaml.safe_dump(config, sort_keys=False))
    name = f"k3dm-alertmanager-test-{os.getpid()}"
    run(
        "docker",
        "run",
        "-d",
        "--rm",
        "--name",
        name,
        "--add-host",
        "host.docker.internal:host-gateway",
        "-p",
        "127.0.0.1::9093",
        "-v",
        f"{config_path}:/etc/alertmanager/alertmanager.yml:ro",
        ALERTMANAGER_IMAGE,
        "--config.file=/etc/alertmanager/alertmanager.yml",
    )
    try:
        port = int(run("docker", "port", name, "9093/tcp").stdout.rsplit(":", 1)[1])
        endpoint = f"http://127.0.0.1:{port}"
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                urlopen(f"{endpoint}/-/ready", timeout=1).read()
                break
            except (URLError, OSError):
                time.sleep(0.1)
        else:
            raise AssertionError("Alertmanager did not become ready")
        yield endpoint, sink
    finally:
        subprocess.run(("docker", "rm", "-f", name), capture_output=True, text=True)
        server.shutdown()


def post(
    endpoint: str,
    labels: dict[str, str],
    ends_at: str | None = None,
    starts_at: str | None = None,
) -> None:
    start = time.time() - 30 if ends_at and starts_at is None else time.time()
    starts_at = starts_at or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start))
    alert = {
        "labels": labels,
        "annotations": {"summary": "behaviour test"},
        "startsAt": starts_at,
        "endsAt": ends_at or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 300)),
        "generatorURL": "http://example.invalid/test",
    }
    request = Request(
        f"{endpoint}/api/v2/alerts",
        data=json.dumps([alert]).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=3):
        pass


def wait_for(predicate, timeout: float = 20) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    assert predicate(), "timed out waiting for Alertmanager notification"


def firing(name: str = "NotifyBehaviour", severity: str = "critical", cluster: str = "hub") -> dict[str, str]:
    return {"alertname": name, "severity": severity, "cluster": cluster, "instance": "test-1"}


def test_deduplicates_repeated_firing_alerts(alertmanager) -> None:
    endpoint, sink = alertmanager
    for _ in range(5):
        post(endpoint, firing())
        time.sleep(0.15)
    wait_for(lambda: len(sink.get("/sms-critical")) >= 1)
    time.sleep(1)
    assert [message["status"] for message in sink.get("/sms-critical")] == ["firing"]


def test_repeats_firing_alert_after_repeat_interval(alertmanager) -> None:
    endpoint, sink = alertmanager
    starts_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    started = time.monotonic()
    while time.monotonic() - started < 15:
        post(endpoint, firing(), starts_at=starts_at)
        time.sleep(1)
    wait_for(lambda: len(sink.get("/sms-critical")) >= 2)
    messages = sink.get("/sms-critical")
    assert len(messages) >= 2
    assert len(messages) <= math.ceil(15 / 6) + 1


def test_sms_sends_resolved_notification(alertmanager) -> None:
    endpoint, sink = alertmanager
    starts_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 30))
    post(endpoint, firing(), starts_at=starts_at)
    wait_for(lambda: any(message["status"] == "firing" for message in sink.get("/sms-critical")))
    ended = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 1))
    post(endpoint, firing(), ended, starts_at=starts_at)
    wait_for(lambda: any(message["status"] == "resolved" for message in sink.get("/sms-critical")))


def test_email_sends_resolved_notification(alertmanager) -> None:
    endpoint, sink = alertmanager
    labels = firing("WarningNotifyBehaviour", "warning")
    starts_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 30))
    post(endpoint, labels, starts_at=starts_at)
    wait_for(lambda: any(message["status"] == "firing" for message in sink.get("/platform-warning")))
    ended = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 1))
    post(endpoint, labels, ended, starts_at=starts_at)
    wait_for(lambda: any(message["status"] == "resolved" for message in sink.get("/platform-warning")))


def test_acg_critical_alert_stays_email_only(alertmanager) -> None:
    endpoint, sink = alertmanager
    post(endpoint, firing(cluster="acg"))
    wait_for(lambda: len(sink.get("/platform-warning")) >= 1)
    time.sleep(1)
    assert sink.get("/sms-critical") == []


def test_trivy_critical_alert_is_not_delivered(alertmanager) -> None:
    endpoint, sink = alertmanager
    post(endpoint, firing("TrivyCriticalVulnerabilityDetected"))
    time.sleep(2)
    assert sink.get() == []


def test_resolved_text_templates_render_with_amtool(tmp_path: Path) -> None:
    config = render_template(tmp_path / "rendered.yaml")
    data = {
        "receiver": "test",
        "status": "resolved",
        "groupLabels": {"alertname": "TemplateNotifyBehaviour", "cluster": "hub"},
        "commonLabels": {"alertname": "TemplateNotifyBehaviour", "severity": "critical", "cluster": "hub"},
        "commonAnnotations": {},
        "externalURL": "http://example.invalid",
        "alerts": [{
            "status": "resolved",
            "labels": {"alertname": "TemplateNotifyBehaviour", "severity": "critical", "cluster": "hub"},
            "annotations": {},
            "startsAt": "2026-10-09T00:00:00Z",
            "endsAt": "2026-10-09T00:01:00Z",
            "generatorURL": "http://example.invalid/test",
        }],
    }
    data_path = tmp_path / "data.json"
    data_path.write_text(json.dumps(data))
    template_dir = tmp_path / "templates"
    template_dir.mkdir()
    (template_dir / "empty.tmpl").write_text("")
    for receiver in ("sms-critical", "platform-warning"):
        receiver_config = next(item for item in config["receivers"] if item["name"] == receiver)
        text_template = receiver_config["email_configs"][0]["text"]
        result = run(
            "docker", "run", "--rm",
            "-v", f"{template_dir}:/tmp/templates:ro",
            "-v", f"{data_path}:/tmp/data.json:ro",
            "--entrypoint=amtool", ALERTMANAGER_IMAGE, "template", "render",
            "--template.glob=/tmp/templates/*.tmpl",
            f"--template.text={text_template}",
            "--template.data=/tmp/data.json",
            check=False,
        )
        assert result.returncode == 0, result.stderr
        rendered = result.stdout
        assert "RESOLVED" in rendered
        assert "TemplateNotifyBehaviour" in rendered
