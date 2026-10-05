"""Tests for the owner dashboard. Run from owner-dashboard/:

    python -m unittest discover -s tests -v
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from eventlens_dashboard import demo, server, store  # noqa: E402
from eventlens_dashboard.__main__ import build_demo_page, main  # noqa: E402


def small_db():
    """Three installs, two accounts, a handful of sessions: exact numbers."""
    db = store.connect(":memory:")
    store.ingest(db, [
        {"type": "install", "install_id": "i1", "at": "2026-09-01T10:00:00Z"},
        {"type": "install", "install_id": "i2", "at": "2026-09-01T11:00:00Z"},
        {"type": "install", "install_id": "i3", "at": "2026-09-02T11:00:00Z"},
        {"type": "activity", "install_id": "i1", "kind": "tutorial_started", "at": "2026-09-01T10:00:00Z"},
        {"type": "activity", "install_id": "i2", "kind": "tutorial_started", "at": "2026-09-01T11:00:00Z"},
        {"type": "activity", "install_id": "i3", "kind": "tutorial_started", "at": "2026-09-02T11:00:00Z"},
        {"type": "activity", "install_id": "i1", "kind": "tutorial_finished", "at": "2026-09-01T10:03:00Z"},
        {"type": "activity", "install_id": "i2", "kind": "tutorial_finished", "at": "2026-09-01T11:03:00Z"},
        {"type": "activity", "install_id": "i1", "kind": "signup_started", "at": "2026-09-01T10:04:00Z"},
        {"type": "activity", "install_id": "i2", "kind": "signup_started", "at": "2026-09-01T11:04:00Z"},
        {"type": "account", "account_id": "a1", "install_id": "i1", "method": "email", "at": "2026-09-01T10:05:00Z"},
        {"type": "account", "account_id": "a2", "install_id": "i2", "method": "web3", "at": "2026-09-01T11:05:00Z"},
        {"type": "activity", "account_id": "a1", "kind": "event_created", "at": "2026-09-01T10:10:00Z", "value": 1},
        {"type": "activity", "account_id": "a1", "kind": "event_described", "at": "2026-09-01T10:11:00Z"},
        {"type": "session", "session_id": "s1", "account_id": "a1", "at": "2026-09-01T10:05:00Z", "minutes": 9},
        {"type": "session", "session_id": "s2", "account_id": "a1", "at": "2026-09-30T09:00:00Z", "minutes": 2, "crashed": True, "app_version": "1.1.0"},
        {"type": "crash", "crash_id": "c1", "session_id": "s2", "account_id": "a1", "at": "2026-09-30T09:02:00Z", "signature": "StateError", "app_version": "1.1.0"},
        {"type": "session", "session_id": "s3", "account_id": "a2", "at": "2026-09-01T11:06:00Z", "minutes": 1},
    ])
    return db


class MetricsTest(unittest.TestCase):
    def test_exact_measures_on_a_small_library(self):
        db = small_db()
        m = store.metrics(db, "7", now=datetime(2026, 9, 30, 12))
        s = m["summary"]
        self.assertEqual(s["accounts_total"], 2)
        self.assertEqual(s["accounts_active"], 1)          # only a1 came back
        self.assertEqual(s["utilization_rate"], 0.5)
        self.assertEqual(s["dau"], 1)
        self.assertEqual(s["crash_free_sessions"], 0.0)    # 1 of 1 crashed
        self.assertEqual(m["crashes"]["top"][0]["signature"], "StateError")

        m = store.metrics(db, "all", now=datetime(2026, 9, 30, 12))
        reach = {r["key"]: r["count"] for r in m["reach"]}
        self.assertEqual(reach["installs"], 3)
        self.assertEqual(reach["tutorial_finished"], 2)
        self.assertEqual(reach["signup_completed"], 2)
        self.assertEqual(reach["event_created"], 1)
        self.assertEqual(reach["event_described"], 1)
        self.assertEqual(reach["graph_unlocked"], 0)
        methods = {x["method"]: x["count"] for x in m["signup_methods"]}
        self.assertEqual(methods, {"email": 1, "phone": 0, "google": 0, "web3": 1})
        depth = {d["label"]: d["count"] for d in m["depth"]}
        self.assertEqual(depth["0 events"], 1)
        self.assertEqual(depth["1-4"], 1)
        self.assertEqual(m["lifetime"]["hours_in_app"], 0.2)

    def test_demo_data_is_repeatable_and_sane(self):
        a, b = store.connect(":memory:"), store.connect(":memory:")
        self.assertEqual(demo.generate(a), demo.generate(b))
        for window in store.WINDOWS:
            m = store.metrics(a, window)
            self.assertEqual(m["source"], "demo")
            s = m["summary"]
            self.assertTrue(0 <= s["utilization_rate"] <= 1)
            self.assertTrue(0 <= s["stickiness"] <= 1)
            self.assertTrue(0.98 <= s["crash_free_sessions"] <= 1)
            self.assertLessEqual(s["dau"], s["wau"])
            self.assertLessEqual(s["wau"], s["mau"])
            counts = [r["count"] for r in m["reach"]]
            self.assertEqual(counts, sorted(counts, reverse=True), window)
            signup = [r["count"] for r in m["signup"]]
            self.assertEqual(signup, sorted(signup, reverse=True), window)
            self.assertAlmostEqual(sum(d["share"] for d in m["depth"]), 1, places=2)
            for row in m["retention"]:
                for value in row["weeks"]:
                    self.assertTrue(value is None or 0 <= value <= 1)
            self.assertGreater(len(m["daily"]), 0)

    def test_ai_allowance_counts(self):
        db = small_db()
        store.ingest(db, [
            {"type": "activity", "account_id": "a1", "kind": "ai_allowance_reached", "at": "2026-09-30T09:00:00Z"},
            {"type": "activity", "account_id": "a1", "kind": "ai_topup", "at": "2026-09-30T09:05:00Z"},
            {"type": "activity", "account_id": "a2", "kind": "ai_allowance_reached", "at": "2026-09-30T10:00:00Z"},
        ])
        m = store.metrics(db, "7", now=datetime(2026, 9, 30, 12))
        use = {f["key"]: (f["total"], f["accounts"]) for f in m["features"]}
        self.assertEqual(use["ai_allowance_reached"], (2, 2))
        self.assertEqual(use["ai_topup"], (1, 1))

    def test_stage2_features_are_counted_without_their_content(self):
        db = small_db()
        store.ingest(db, [
            {"type": "activity", "account_id": "a1", "kind": "free_write_saved", "at": "2026-09-30T09:00:00Z"},
            {"type": "activity", "account_id": "a1", "kind": "free_write_labelled", "at": "2026-09-30T09:00:30Z"},
            {"type": "activity", "account_id": "a1", "kind": "mind_map_opened", "at": "2026-09-30T09:01:00Z"},
            {"type": "activity", "account_id": "a1", "kind": "mind_map_centered", "at": "2026-09-30T09:02:00Z", "value": 2},
        ])
        m = store.metrics(db, "7", now=datetime(2026, 9, 30, 12))
        use = {f["key"]: (f["total"], f["accounts"]) for f in m["features"]}
        self.assertEqual(use["free_write_saved"], (1, 1))
        self.assertEqual(use["free_write_labelled"], (1, 1))
        self.assertEqual(use["mind_map_opened"], (1, 1))
        self.assertEqual(use["mind_map_centered"], (2, 1))
        # Only counts are stored: the activity table has no text column.
        columns = {r[1] for r in db.execute("PRAGMA table_info(activity)")}
        self.assertEqual(columns, {"id", "install_id", "account_id", "at", "kind", "value"})

        demo_db = store.connect(":memory:")
        demo.generate(demo_db)
        demo_use = {f["key"]: f["total"] for f in store.metrics(demo_db, "all")["features"]}
        for key in ("free_write_saved", "free_write_labelled",
                    "mind_map_opened", "mind_map_centered"):
            self.assertGreater(demo_use[key], 0, key)

    def test_label_reviews_give_a_rejection_rate(self):
        db = small_db()
        m = store.metrics(db, "7", now=datetime(2026, 9, 30, 12))
        self.assertIsNone(m["labels"]["rejection_rate"])   # nothing reviewed
        records = [{"type": "activity", "account_id": "a1", "kind": kind,
                    "at": "2026-09-30T09:0%d:00Z" % i}
                   for i, kind in enumerate(["free_write_labelled"] * 2 + ["label_confirmed"] * 3
                                            + ["label_rejected", "label_relabelled"])]
        store.ingest(db, records)
        labels = store.metrics(db, "7", now=datetime(2026, 9, 30, 12))["labels"]
        self.assertEqual((labels["labelled"], labels["confirmed"], labels["rejected"],
                          labels["relabelled"], labels["reviewed"]), (2, 3, 1, 1, 4))
        self.assertEqual(labels["rejection_rate"], 0.25)
        self.assertGreaterEqual(labels["rejection_rate"], labels["alert"])

        demo_db = store.connect(":memory:")
        demo.generate(demo_db)
        demo_labels = store.metrics(demo_db, "all")["labels"]
        self.assertGreater(demo_labels["reviewed"], 0)
        self.assertTrue(0 < demo_labels["rejection_rate"] < demo_labels["watch"] * 2)

    def test_unfinished_retention_weeks_stay_blank(self):
        db = store.connect(":memory:")
        demo.generate(db)
        m = store.metrics(db, "all")
        newest = m["retention"][-1]
        self.assertTrue(all(v is None for v in newest["weeks"]))

    def test_bad_window(self):
        with self.assertRaises(ValueError):
            store.metrics(store.connect(":memory:"), "12")


class IngestTest(unittest.TestCase):
    def test_bad_records_reject_the_whole_batch(self):
        db = store.connect(":memory:")
        for records, message in (
            ("nope", "must be a list"),
            ([{"type": "account", "account_id": "a", "at": "2026-01-01", "method": "fax"}], "unknown sign-up method"),
            ([{"type": "activity", "kind": "hack", "install_id": "i", "at": "2026-01-01"}], "unknown activity"),
            ([{"type": "activity", "kind": "app_open", "at": "2026-01-01"}], "needs install_id"),
            ([{"type": "session", "session_id": "s", "at": "yesterday"}], "bad value"),
            ([{"type": "install", "install_id": "ok", "at": "2026-01-01"}, {"type": "mystery"}], "unknown record type"),
        ):
            with self.assertRaises(store.IngestError) as caught:
                store.ingest(db, records)
            self.assertIn(message, str(caught.exception))
        self.assertEqual(db.execute("SELECT COUNT(*) FROM installs").fetchone()[0], 0)

    def test_times_with_zones_are_stored_as_utc(self):
        db = store.connect(":memory:")
        store.ingest(db, [{"type": "install", "install_id": "i", "at": "2026-03-01T09:00:00-05:00"}])
        self.assertEqual(db.execute("SELECT first_seen FROM installs").fetchone()[0], "2026-03-01T14:00:00")


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.config = {"ingest_token": "in-token", "admin_token": "admin-token"}
        db_path = os.path.join(self.tmp.name, "m.db")
        demo.generate(store.connect(db_path))
        self.httpd = server.DashboardServer(db_path, self.config, 0)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.base = self.httpd.url

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=10) as r:
            return r.status, r.headers, r.read().decode()

    def post(self, path, body, token=None):
        request = urllib.request.Request(
            self.base + path, data=json.dumps(body).encode(), method="POST",
            headers={"Content-Type": "application/json",
                     **({"Authorization": "Bearer " + token} if token else {})})
        try:
            with urllib.request.urlopen(request, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_only_this_computer_can_connect(self):
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")

    def test_page_and_metrics(self):
        status, headers, page = self.get("/")
        self.assertEqual(status, 200)
        self.assertTrue(page.startswith("<!doctype html>"))
        self.assertIn("<title>EventLens Owner Dashboard</title>", page)
        self.assertIn("no-store", headers["Cache-Control"])
        for window in ("7", "30", "90", "365", "all"):
            status, _, body = self.get("/api/metrics?window=" + window)
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body)["window"], window)
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.get("/api/metrics?window=5")
        self.assertEqual(caught.exception.code, 400)

    def test_ingest_needs_the_token(self):
        record = {"records": [{"type": "install", "install_id": "new", "at": "2026-10-03T12:00:00Z"}]}
        self.assertEqual(self.post("/api/ingest", record)[0], 401)
        self.assertEqual(self.post("/api/ingest", record, "wrong")[0], 401)
        self.assertEqual(self.post("/api/ingest", record, "in-token"), (200, {"stored": 1}))
        status, body = self.post("/api/ingest", {"records": [{"type": "bad"}]}, "in-token")
        self.assertEqual(status, 400)
        self.assertIn("unknown record type", body["error"])
        # The ingest token can't end the hosting.
        self.assertEqual(self.post("/api/shutdown", {}, "in-token")[0], 401)


class CommandLineTest(unittest.TestCase):
    def test_setup_start_status_stop_in_the_background(self):
        with tempfile.TemporaryDirectory() as folder:
            def run(*args):
                return subprocess.run(
                    [sys.executable, "-m", "eventlens_dashboard", "--data-dir", folder] + list(args),
                    cwd=str(ROOT), capture_output=True, text=True, timeout=120)

            self.assertIn("Not set up yet", run("start").stderr)
            out = run("setup", "--demo", "--port", "0").stdout
            self.assertIn("Loaded demo data", out)
            config = json.loads(Path(folder, "config.json").read_text())
            self.assertNotEqual(config["ingest_token"], config["admin_token"])
            self.assertIn("keeping your tokens", run("setup").stdout)

            port = _free_port()
            started = run("start", "--background", "--no-browser", "--port", str(port))
            self.assertIn("Started in the background", started.stdout, started.stdout + started.stderr)
            self.assertIn("Running at http://127.0.0.1:%d/" % port, run("status").stdout)
            self.assertIn("Already running", run("start", "--background", "--no-browser").stdout)
            self.assertIn("Hosting ended", run("stop").stdout)
            self.assertIn("Not running", run("status").stdout)
            self.assertIn("Not running", run("stop").stdout)

            self.assertIn("--yes", run("reset").stdout)
            self.assertIn("All metrics deleted", run("reset", "--yes").stdout)

    def test_demo_page_is_self_contained(self):
        page = build_demo_page()
        self.assertIn("<title>EventLens Owner Dashboard</title>", page)
        self.assertNotIn('type="application/json">null<', page)
        data = page.split('<script id="embedded-metrics" type="application/json">')[1].split("</script>")[0]
        parsed = json.loads(data)
        self.assertEqual(set(parsed), set(store.WINDOWS) | {"features"})
        self.assertEqual(len(parsed["features"]["details"]), 14)
        self.assertNotIn("<!doctype", page.lower())  # the artifact host adds it
        hosts = {h.split("/")[2] for h in __import__("re").findall(r'(?:src|href)="(https://[^"]+)"', page)}
        self.assertLessEqual(hosts, {"fonts.googleapis.com"})
        with tempfile.TemporaryDirectory() as folder:
            target = os.path.join(folder, "demo.html")
            self.assertEqual(main(["export-demo", target]), 0)
            self.assertTrue(Path(target).read_text().startswith("<title>"))


def _free_port():
    import socket
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


if __name__ == "__main__":
    unittest.main()
