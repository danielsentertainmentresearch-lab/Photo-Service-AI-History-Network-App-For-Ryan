"""The local web server. It listens on 127.0.0.1 only, so nothing outside
this computer can reach it.

Routes
------
GET  /                      the dashboard page
GET  /api/health            {"ok": true}
GET  /api/metrics?window=30 every measure for the last 7/30/90/365/all days
POST /api/ingest            records from the app (needs the ingest token)
POST /api/shutdown          ends this hosting (needs the admin token)
"""

import hmac
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib import resources
from urllib.parse import parse_qs, urlparse

from . import store

HOST = "127.0.0.1"
MAX_BODY = 5 * 1024 * 1024

PAGE_SHELL = (
    '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1, '
    'viewport-fit=cover">\n</head>\n<body>\n%s\n</body>\n</html>\n'
)


def page_fragment():
    return resources.files(__package__).joinpath("web/index.html").read_text(
        encoding="utf-8")


def full_page(data=None):
    """The dashboard page. With [data] (metrics for every window), the page
    is self-contained and needs no server, as in the shareable demo."""
    fragment = page_fragment()
    if data is not None:
        embedded = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
        fragment = fragment.replace(
            '<script id="embedded-metrics" type="application/json">null</script>',
            '<script id="embedded-metrics" type="application/json">%s</script>'
            % embedded)
    return fragment


class _Handler(BaseHTTPRequestHandler):
    server_version = "EventLensDashboard/1.0"

    def log_message(self, fmt, *args):
        if self.server.log is not None:
            self.server.log.write("%s %s\n" % (self.log_date_time_string(),
                                               fmt % args))
            self.server.log.flush()

    def _send(self, status, body, content_type="application/json"):
        payload = body if isinstance(body, bytes) else (
            json.dumps(body).encode("utf-8") if content_type ==
            "application/json" else body.encode("utf-8"))
        self.send_response(status)
        self.send_header("Content-Type", content_type + "; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(payload)

    def _authorized(self, token):
        header = self.headers.get("Authorization", "")
        given = header[7:] if header.startswith("Bearer ") else ""
        return bool(token) and hmac.compare_digest(given.encode(), token.encode())

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in ("/", "/index.html"):
            self._send(200, PAGE_SHELL % full_page(), "text/html")
        elif url.path == "/api/health":
            self._send(200, {"ok": True})
        elif url.path == "/api/metrics":
            window = parse_qs(url.query).get("window", ["30"])[0]
            if window not in store.WINDOWS:
                self._send(400, {"error": "window must be one of "
                                 + ", ".join(store.WINDOWS)})
                return
            with self.server.lock:
                data = store.metrics(self.server.db, window)
            self._send(200, data)
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            self._send(413, {"error": "request too large"})
            return
        raw = self.rfile.read(length) if length else b""
        if url.path == "/api/ingest":
            if not self._authorized(self.server.config.get("ingest_token")):
                self._send(401, {"error": "wrong or missing ingest token"})
                return
            try:
                body = json.loads(raw or b"{}")
                with self.server.lock:
                    count = store.ingest(self.server.db, body.get("records"))
            except (ValueError, AttributeError) as error:
                self._send(400, {"error": str(error)})
                return
            self._send(200, {"stored": count})
        elif url.path == "/api/shutdown":
            if not self._authorized(self.server.config.get("admin_token")):
                self._send(401, {"error": "wrong or missing admin token"})
                return
            self._send(200, {"stopping": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            self._send(404, {"error": "not found"})


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, db_path, config, port, log=None):
        super().__init__((HOST, port), _Handler)
        self.db = store.connect(db_path)
        self.config = config
        self.lock = threading.Lock()
        self.log = log

    @property
    def url(self):
        return "http://%s:%d/" % (HOST, self.server_address[1])

    def server_close(self):
        super().server_close()
        self.db.close()


def write_pid(path, port):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({"pid": os.getpid(), "port": port}, handle)
