"""The local web server. It listens on 127.0.0.1 only, so nothing outside
this computer can reach it.

Routes
------
GET  /                      the dashboard page
GET  /api/health            {"ok": true}
GET  /api/metrics?window=30 every measure for the last 7/30/90/365/all days
GET  /api/features          the feature-test archive (top level)
GET  /api/features/export   archive downloads (?kind=simple|complete&format=csv|json)
GET  /api/features/ID       one archive data point, with its review catalog
GET  /api/features/ID/export  downloads (?kind=simple|complete|custom
                            &format=csv|json|kit, plus columns and filters)
GET  /api/notebook/open     prepares a fresh notebook for a feature
GET  /notebook/...          the built-in Jupyter notebook (JupyterLite)
POST /api/ingest            records from the app (needs the ingest token)
POST /api/shutdown          ends this hosting (needs the admin token)
"""

import hmac
import itertools
import json
import mimetypes
import os
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib import resources
from urllib.parse import parse_qs, quote, unquote, urlparse

from . import features, store

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


NOTEBOOK_MISSING = (
    "<!doctype html><meta charset=utf-8><title>Notebook not set up</title>"
    "<body style='font:15px system-ui;padding:24px;max-width:60ch'>"
    "<h2>The built-in notebook isn't set up yet</h2><p>Run this once, with an "
    "internet connection, then try again:</p><pre>python -m eventlens_dashboard "
    "notebook-setup</pre></body>")


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
        if isinstance(body, bytes):
            payload = body
        elif content_type == "application/json" and not isinstance(body, str):
            payload = json.dumps(body).encode("utf-8")
        else:
            payload = body.encode("utf-8")
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

    def _download(self, name, content_type, payload):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Disposition",
                         "attachment; filename=\"%s\"" % name)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _query(self, url):
        return {k: v[-1] for k, v in parse_qs(url.query).items()}

    def _features_get(self, url):
        parts = [unquote(p) for p in url.path.split("/")[3:] if p]
        query = self._query(url)
        with self.server.lock:
            db = self.server.db
            try:
                if not parts:
                    self._send(200, {
                        "rows": features.archive(db),
                        "summary": features.summary(db),
                        "statuses": features.STATUS_LABELS,
                        "status_date_labels": features.STATUS_DATE_LABELS,
                        "notebook": {"installed": self.server.notebook_ready()},
                    })
                elif parts == ["export"]:
                    self._download(*features.archive_export(
                        db, query.get("kind", "simple"), query.get("format", "csv")))
                elif len(parts) == 1:
                    data = features.detail(db, parts[0])
                    if data is None:
                        self._send(404, {"error": "no such feature"})
                    else:
                        self._send(200, data)
                elif len(parts) == 2 and parts[1] == "export":
                    self._download(*features.feature_export(
                        db, parts[0], query.get("kind", "simple"),
                        query.get("format", "csv"), query))
                else:
                    self._send(404, {"error": "not found"})
            except KeyError:
                self._send(404, {"error": "no such feature"})
            except ValueError as error:
                self._send(400, {"error": str(error)})

    def _notebook_open(self, url):
        query = self._query(url)
        if not self.server.notebook_ready():
            self._send(409, {"error": "The built-in notebook isn't set up yet. "
                             "Run: python -m eventlens_dashboard notebook-setup"})
            return
        with self.server.lock:
            data = features.detail(self.server.db, query.get("feature", ""))
            if data is None:
                self._send(404, {"error": "no such feature"})
                return
            try:
                columns = features.pick_columns(query.get("columns"))
            except ValueError as error:
                self._send(400, {"error": str(error)})
                return
            rows = features.filter_reviews(data["reviews"], query)
        name = self.server.new_notebook(data, rows, columns, query)
        self._send(200, {"url": "/notebook/notebooks/index.html?path=" +
                         quote(name), "notebook": name, "rows": len(rows)})

    def _notebook_static(self, url):
        rel = unquote(url.path[len("/notebook/"):]) or "index.html"
        if rel in ("api/contents/all.json",):
            self._send(200, self.server.notebook_listing())
            return
        if rel.startswith("files/"):
            item = self.server.notebook_file(rel[len("files/"):])
            if item is None:
                self._send(404, {"error": "not found"})
            else:
                self._send(200, item[1], item[0])
            return
        site = self.server.notebook_dir
        if not self.server.notebook_ready():
            self._send(404, NOTEBOOK_MISSING, "text/html")
            return
        path = os.path.realpath(os.path.join(site, rel))
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        if not path.startswith(os.path.realpath(site) + os.sep) or \
                not os.path.isfile(path):
            self._send(404, {"error": "not found"})
            return
        kind = mimetypes.guess_type(path)[0] or "application/octet-stream"
        if path.endswith((".mjs", ".js")):
            kind = "text/javascript"
        elif path.endswith(".wasm"):
            kind = "application/wasm"
        with open(path, "rb") as handle:
            payload = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/features" or url.path.startswith("/api/features/"):
            self._features_get(url)
        elif url.path == "/api/notebook/open":
            self._notebook_open(url)
        elif url.path.startswith("/notebook/") or url.path == "/notebook":
            if url.path == "/notebook":
                url = urlparse("/notebook/")
            self._notebook_static(url)
        elif url.path in ("/", "/index.html"):
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

    def __init__(self, db_path, config, port, log=None, notebook_dir=None):
        super().__init__((HOST, port), _Handler)
        self.db = store.connect(db_path)
        self.config = config
        self.lock = threading.Lock()
        self.log = log
        self.notebook_dir = notebook_dir
        # Fresh notebooks handed to the built-in JupyterLite: name -> (type,
        # text). Kept in memory only, newest 40.
        self._notebooks = {}
        self._notebook_ids = itertools.count(1)

    def notebook_ready(self):
        return bool(self.notebook_dir) and os.path.isfile(
            os.path.join(self.notebook_dir, "notebooks", "index.html"))

    def new_notebook(self, data, rows, columns, query):
        """Makes a new notebook and its data file; each open starts fresh."""
        feature = data["archive"]
        stamp = datetime.now().strftime("%H%M%S")
        base = "%s-%s-%d" % (feature["feature_id"], stamp,
                             next(self._notebook_ids))
        filters = {k: query[k] for k in features.FILTER_KEYS if query.get(k)}
        notebook = features.notebook(feature, base + ".csv", columns, filters)
        with self.lock:
            self._notebooks[base + ".csv"] = (
                "text/csv", features.to_csv(rows, columns))
            self._notebooks[base + ".ipynb"] = (
                "application/json", json.dumps(notebook))
            while len(self._notebooks) > 80:
                self._notebooks.pop(next(iter(self._notebooks)))
        return base + ".ipynb"

    def notebook_file(self, name):
        with self.lock:
            return self._notebooks.get(name)

    def notebook_listing(self):
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        with self.lock:
            items = list(self._notebooks.items())
        content = [{
            "name": name, "path": name, "content": None, "format": None,
            "mimetype": None if name.endswith(".ipynb") else kind,
            "type": "notebook" if name.endswith(".ipynb") else "file",
            "size": len(text.encode("utf-8")), "created": now,
            "last_modified": now, "writable": True, "hash": None,
            "hash_algorithm": None,
        } for name, (kind, text) in items]
        return {"name": "", "path": "", "type": "directory", "format": "json",
                "mimetype": None, "content": content, "size": None,
                "created": now, "last_modified": now, "writable": True,
                "hash": None, "hash_algorithm": None}

    @property
    def url(self):
        return "http://%s:%d/" % (HOST, self.server_address[1])

    def server_close(self):
        super().server_close()
        self.db.close()


def write_pid(path, port):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({"pid": os.getpid(), "port": port}, handle)
