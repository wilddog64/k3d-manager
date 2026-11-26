"""Small loopback Pushgateway with replace-on-PUT grouping semantics."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading


class FakePushgateway:
    def __init__(self, fail_health=False, fail_put=False):
        self.groups = {}
        self.requests = []
        self.fail_health = fail_health
        self.fail_put = fail_put
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests.append(("GET", self.path, ""))
                self.send_response(500 if owner.fail_health else 200)
                self.end_headers()

            def _write(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
                owner.requests.append((self.command, self.path, body))
                if self.command == "PUT" and not owner.fail_put:
                    owner.groups[self.path] = body
                elif self.command == "DELETE":
                    owner.groups.pop(self.path, None)
                self.send_response(500 if owner.fail_put and self.command == "PUT" else 202)
                self.end_headers()

            do_PUT = _write
            do_POST = _write
            do_DELETE = _write

            def log_message(self, *_args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_args):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
