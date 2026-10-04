"""Tests for the feature-test archive. Run from owner-dashboard/:

    python -m unittest discover -s tests -v
"""

import csv
import io
import json
import os
import sqlite3
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from eventlens_dashboard import demo, features, server, store  # noqa: E402

_DB = None


def demo_db():
    global _DB
    if _DB is None:
        _DB = store.connect(":memory:")
        demo.generate(_DB)
    return _DB


class ArchiveTest(unittest.TestCase):
    def test_top_level_columns_and_statuses(self):
        rows = features.archive(demo_db())
        self.assertEqual(len(rows), 14)
        self.assertEqual([r["row"] for r in rows], list(range(1, 15)))
        self.assertEqual(features.ARCHIVE_COLUMNS[:3], ("row", "archive_status", "status_date"))
        self.assertEqual({r["archive_status"] for r in rows}, set(store.FEATURE_STATUSES))
        for r in rows:
            self.assertRegex(r["status_date"], r"^\d{4}-\d\d-\d\d$")
            if r["archive_status"] == "scheduled":
                self.assertEqual(r["reviews"], 0)
                self.assertEqual(r["stage"], "Not started")
                self.assertGreater(r["status_date"], "2026-10-03")

    def test_the_90_percent_rule_and_collectables(self):
        db = demo_db()
        live = db.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        for r in features.archive(db):
            if r["outcome"] == "dedicated update":
                self.assertGreaterEqual(r["yes_share"], 0.9)
                self.assertGreater(r["collectables"], 0)
                self.assertLessEqual(r["collectables"], live)
            else:
                self.assertEqual(r["collectables"], 0)
            if r["outcome"] in ("next major version", "holiday or promotional event"):
                self.assertLess(r["yes_share"], 0.9)

    def test_round_aggregates_add_up(self):
        db = demo_db()
        for r in features.archive(db):
            d = features.detail(db, r["feature_id"])
            self.assertEqual(sum(x["reviews"] for x in d["rounds"]), r["reviews"])
            for rd in d["rounds"]:
                if rd["round_kind"] == "feedback":
                    self.assertEqual(sum(rd["rating_%d" % k] for k in range(1, 6)), rd["reviews"])
                    self.assertIsNone(rd["yes_share"])
                else:
                    self.assertEqual(rd["yes"] + rd["no"] + rd["abstain"], rd["reviews"])
                self.assertLessEqual(rd["reviewers"], rd["invited"])

    def test_summary(self):
        s = features.summary(demo_db())
        self.assertEqual(sum(s["by_status"].values()), s["total"])
        self.assertEqual(s["open_rounds"], 2)
        self.assertTrue(0 < s["avg_response_rate"] <= 1)
        m = store.metrics(demo_db(), "30")
        self.assertEqual(m["feature_testing"]["total"], 14)
        self.assertEqual(m["lifetime"]["feature_reviews"], s["reviews"])
        review_use = m["features"][-1]
        self.assertEqual(review_use["key"], "feature_review")
        self.assertLessEqual(review_use["share_of_active"], 1)

    def test_unknown_feature(self):
        self.assertIsNone(features.detail(demo_db(), "FT-99"))
        with self.assertRaises(KeyError):
            features.feature_export(demo_db(), "FT-99", "simple", "csv", {})


class CatalogFilterTest(unittest.TestCase):
    def setUp(self):
        self.d = features.detail(demo_db(), "FT-03")
        self.rows = self.d["reviews"]

    def test_filters_offer_only_what_each_round_contains(self):
        rounds = self.d["filters"]["rounds"]
        vote_round = [r for r in self.d["rounds"] if r["round_kind"] == "vote"][0]["round"]
        self.assertEqual(rounds[str(vote_round)]["rating"], [])
        self.assertTrue(rounds[str(vote_round)]["vote"])
        self.assertEqual(rounds["1"]["vote"], [])
        self.assertTrue(rounds["1"]["rating"])
        self.assertEqual(sum(r["count"] for r in rounds.values()), len(self.rows))

    def test_each_filter(self):
        f = features.filter_reviews
        self.assertTrue(all(r["round"] == 1 for r in f(self.rows, {"round": "1"})))
        fives = f(self.rows, {"rating": "5"})
        self.assertTrue(fives and all(r["rating"] == 5 for r in fives))
        both = f(self.rows, {"rating": "4,5"})
        self.assertGreater(len(both), len(fives))
        self.assertTrue(all(r["vote"] == "no" for r in f(self.rows, {"vote": "no"})))
        self.assertTrue(all(r["has_comment"] for r in f(self.rows, {"comment": "with"})))
        self.assertTrue(all(not r["has_comment"] for r in f(self.rows, {"comment": "without"})))
        some = self.rows[len(self.rows) // 2]
        dated = f(self.rows, {"from": some["date"], "to": some["date"]})
        self.assertTrue(dated and all(r["date"] == some["date"] for r in dated))
        found = f(self.rows, {"q": some["review_id"].lower()})
        self.assertEqual([r["review_id"] for r in found], [some["review_id"]])
        self.assertEqual(len(f(self.rows, {})), len(self.rows))

    def test_columns(self):
        self.assertEqual(features.pick_columns("vote,round"), ["round", "vote"])
        self.assertEqual(features.pick_columns(""), list(features.REVIEW_COLUMN_NAMES))
        with self.assertRaises(ValueError):
            features.pick_columns("round,password")


class ExportTest(unittest.TestCase):
    def test_simple_complete_and_custom(self):
        db = demo_db()
        name, kind, body = features.feature_export(db, "FT-03", "simple", "csv", {})
        self.assertEqual((name, kind), ("eventlens-ft-03-simple.csv", "text/csv"))
        rows = list(csv.DictReader(io.StringIO(body.decode())))
        # The original columns keep their place; helper columns follow.
        self.assertEqual(list(rows[0])[:len(features.ROUND_COLUMNS)],
                         list(features.ROUND_COLUMNS))
        self.assertEqual(len(rows), 4)

        _, _, body = features.feature_export(db, "FT-03", "complete", "json", {})
        data = json.loads(body)
        self.assertEqual(data["columns"][:len(features.REVIEW_COLUMN_NAMES)],
                         list(features.REVIEW_COLUMN_NAMES))
        self.assertEqual(len(data["rows"]), features.archive(db)[2]["reviews"])

        _, _, body = features.feature_export(
            db, "FT-03", "custom", "csv", {"columns": "round,rating", "rating": "5"})
        rows = list(csv.DictReader(io.StringIO(body.decode())))
        self.assertEqual(list(rows[0]), ["round", "rating", "rating_known"])
        self.assertTrue(all(r["rating"] == "5" and r["rating_known"] == "1"
                            for r in rows))

        with self.assertRaises(ValueError):
            features.feature_export(db, "FT-03", "everything", "csv", {})
        with self.assertRaises(ValueError):
            features.feature_export(db, "FT-03", "simple", "xlsx", {})

    def test_archive_exports(self):
        db = demo_db()
        _, _, body = features.archive_export(db, "simple", "csv")
        rows = list(csv.DictReader(io.StringIO(body.decode())))
        self.assertEqual(len(rows), 14)
        self.assertEqual(list(rows[0])[:3], ["row", "archive_status", "status_date"])
        _, _, body = features.archive_export(db, "complete", "json")
        self.assertEqual(len(json.loads(body)["rows"]), features.summary(db)["reviews"])

    def test_analysis_kit_for_other_tools(self):
        db = demo_db()
        name, kind, body = features.feature_export(
            db, "FT-01", "custom", "kit", {"columns": "round,rating,vote,comment", "round": "1"})
        self.assertEqual(kind, "application/zip")
        with zipfile.ZipFile(io.BytesIO(body)) as kit:
            names = set(kit.namelist())
            base = "eventlens-ft-01-custom"
            self.assertEqual(names, {base + ext for ext in (".csv", ".json", ".ipynb", ".py", ".sqlite")} | {"README.txt"})
            nb = json.loads(kit.read(base + ".ipynb"))
            self.assertEqual(nb["nbformat"], 4)
            self.assertIn(base + ".csv", "".join(nb["cells"][1]["source"]))
            compile(kit.read(base + ".py").decode(), base + ".py", "exec")
            with tempfile.TemporaryDirectory() as folder:
                path = os.path.join(folder, "k.sqlite")
                Path(path).write_bytes(kit.read(base + ".sqlite"))
                con = sqlite3.connect(path)
                count = con.execute("SELECT COUNT(*) FROM reviews").fetchone()[0]
                self.assertTrue(count > 0)
                self.assertEqual(con.execute("SELECT COUNT(*) FROM reviews WHERE round != 1").fetchone()[0], 0)
                self.assertGreater(con.execute("SELECT COUNT(*) FROM rounds").fetchone()[0], 0)
                con.close()
            self.assertIn("round = 1", kit.read("README.txt").decode())

    def test_no_export_has_a_blank_cell(self):
        db = demo_db()
        files = [features.archive_export(db, k, "csv") for k in ("simple", "complete")]
        files += [features.feature_export(db, "FT-01", k, "csv", {})
                  for k in ("simple", "complete", "custom")]
        for name, _, body in files:
            rows = list(csv.reader(io.StringIO(body.decode())))
            for row in rows[1:]:
                self.assertEqual(len(row), len(rows[0]), name)
                self.assertNotIn("", row, name)
        # Helper columns carry the meaning of what was missing.
        _, _, body = features.feature_export(db, "FT-01", "complete", "csv", {})
        rows = list(csv.DictReader(io.StringIO(body.decode())))
        votes = [r for r in rows if r["round_kind"] == "vote"]
        self.assertTrue(votes)
        for r in votes:
            self.assertEqual((r["rating"], r["rating_known"]),
                             (str(features.UNKNOWN_NUMBER), "0"))
            self.assertEqual(r["vote_" + r["vote"]], "1")
        for r in rows:
            self.assertIn(r["reviewed_at_weekday"], [str(d) for d in range(1, 8)])
            self.assertEqual(int(r["vote_yes"]) + int(r["vote_no"]) +
                             int(r["vote_abstain"]) + int(r["vote_none"]), 1)
        # The kit's sqlite and README follow the same rules.
        _, _, body = features.feature_export(db, "FT-01", "complete", "kit", {})
        with zipfile.ZipFile(io.BytesIO(body)) as kit:
            guide = kit.read("README.txt").decode()
            self.assertIn("rating_known", guide)
            self.assertIn(str(features.UNKNOWN_NUMBER), guide)
            nb = json.dumps(json.loads(kit.read("eventlens-ft-01-complete.ipynb")))
            self.assertIn("rating_known", nb)
            self.assertNotIn("dropna", nb)

    def test_notebook_cells_follow_the_columns(self):
        feature = features.archive(demo_db())[0]
        only = features.notebook(feature, "x.csv", ["round"], {})
        text = json.dumps(only)
        self.assertNotIn("vote", text.split("Rows: one per review")[1].split("Columns are")[0].replace("dedicated", ""))
        full = features.notebook(feature, "x.csv", list(features.REVIEW_COLUMN_NAMES), {"round": "1"})
        self.assertGreater(len(full["cells"]), len(only["cells"]))
        self.assertIn("round = 1", full["cells"][0]["source"])


class IngestTest(unittest.TestCase):
    def test_feature_records(self):
        db = store.connect(":memory:")
        store.ingest(db, [
            {"type": "feature", "feature_id": "FT-1", "name": "Test", "category": "frontier",
             "status": "launched", "status_date": "2026-09-01", "at": "2026-08-20"},
            {"type": "feature_round", "feature_id": "FT-1", "round": 1, "kind": "feedback",
             "opened_at": "2026-09-01", "invited": 10},
            {"type": "feature_review", "review_id": "r1", "feature_id": "FT-1", "round": 1,
             "account_id": "a1", "at": "2026-09-02", "rating": 5, "comment": "Great"},
            {"type": "collectable", "feature_id": "FT-1", "account_id": "a1", "at": "2026-09-30"},
        ])
        row = features.archive(db)[0]
        self.assertEqual((row["archive_status"], row["reviews"], row["stage"]),
                         ("launched", 1, "Feedback round 1 open"))
        for bad, message in (
            ({"type": "feature", "feature_id": "x", "name": "n", "category": "magic",
              "status": "launched", "status_date": "2026-01-01", "at": "2026-01-01"}, "unknown category"),
            ({"type": "feature", "feature_id": "x", "name": "n", "category": "new",
              "status": "paused", "status_date": "2026-01-01", "at": "2026-01-01"}, "unknown status"),
            ({"type": "feature_review", "review_id": "r", "feature_id": "x", "round": 1,
              "at": "2026-01-01", "rating": 6}, "rating must be 1 to 5"),
            ({"type": "feature_review", "review_id": "r", "feature_id": "x", "round": 1,
              "at": "2026-01-01", "vote": "maybe"}, "vote must be"),
            ({"type": "feature_review", "review_id": "r", "feature_id": "x", "round": 1,
              "at": "2026-01-01"}, "needs a rating or a vote"),
        ):
            with self.assertRaises(store.IngestError) as caught:
                store.ingest(db, [bad])
            self.assertIn(message, str(caught.exception))


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        db_path = os.path.join(self.tmp.name, "m.db")
        demo.generate(store.connect(db_path))
        self.site = os.path.join(self.tmp.name, "site")
        os.makedirs(os.path.join(self.site, "notebooks"))
        Path(self.site, "notebooks", "index.html").write_text("<p>lite</p>")
        Path(self.tmp.name, "secret.txt").write_text("no")
        self.httpd = server.DashboardServer(db_path, {"ingest_token": "i", "admin_token": "a"}, 0,
                                            notebook_dir=self.site)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.httpd.url.rstrip("/") + path, timeout=10) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read()

    def test_archive_routes_and_downloads(self):
        status, _, body = self.get("/api/features")
        data = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(len(data["rows"]), 14)
        self.assertTrue(data["notebook"]["installed"])
        status, _, body = self.get("/api/features/FT-03")
        self.assertEqual(json.loads(body)["archive"]["feature_id"], "FT-03")
        self.assertEqual(self.get("/api/features/FT-99")[0], 404)
        status, headers, body = self.get("/api/features/FT-03/export?kind=custom&format=csv&columns=round,vote&vote=yes")
        self.assertEqual(status, 200)
        self.assertIn('filename="eventlens-ft-03-custom.csv"', headers["Content-Disposition"])
        self.assertTrue(body.decode().startswith("round,vote"))
        self.assertEqual(self.get("/api/features/FT-03/export?kind=custom&format=csv&columns=nope")[0], 400)
        status, headers, _ = self.get("/api/features/export?kind=complete&format=json")
        self.assertEqual(status, 200)
        self.assertIn("feature-archive-complete.json", headers["Content-Disposition"])

    def test_fresh_notebooks_for_the_built_in_jupyter(self):
        status, _, body = self.get("/api/notebook/open?feature=FT-01&columns=round,rating&rating=5")
        first = json.loads(body)
        self.assertEqual(status, 200)
        self.assertTrue(first["url"].startswith("/notebook/notebooks/index.html?path=FT-01-"))
        second = json.loads(self.get("/api/notebook/open?feature=FT-01")[2])
        self.assertNotEqual(first["notebook"], second["notebook"])
        listing = json.loads(self.get("/notebook/api/contents/all.json")[2])
        names = {c["name"] for c in listing["content"]}
        self.assertIn(first["notebook"], names)
        self.assertIn(first["notebook"].replace(".ipynb", ".csv"), names)
        nb = json.loads(self.get("/notebook/files/" + first["notebook"])[2])
        self.assertEqual(nb["nbformat"], 4)
        data = self.get("/notebook/files/" + first["notebook"].replace(".ipynb", ".csv"))[2].decode()
        self.assertTrue(data.startswith("round,rating,rating_known"))
        self.assertTrue(all(line.endswith(",5,1") for line in data.strip().splitlines()[1:]))
        self.assertEqual(self.get("/notebook/notebooks/")[2], b"<p>lite</p>")
        self.assertEqual(self.get("/notebook/../secret.txt")[0], 404)
        self.assertEqual(self.get("/notebook/%2e%2e/secret.txt")[0], 404)
        self.assertEqual(self.get("/api/notebook/open?feature=FT-99")[0], 404)

    def test_without_the_notebook_installed(self):
        self.httpd.notebook_dir = os.path.join(self.tmp.name, "missing")
        status, _, body = self.get("/api/notebook/open?feature=FT-01")
        self.assertEqual(status, 409)
        self.assertIn("notebook-setup", json.loads(body)["error"])
        status, _, body = self.get("/notebook/notebooks/index.html")
        self.assertEqual(status, 404)
        self.assertIn(b"notebook-setup", body)


if __name__ == "__main__":
    unittest.main()
