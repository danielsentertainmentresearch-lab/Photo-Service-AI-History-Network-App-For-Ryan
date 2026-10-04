"""The feature-test archive: test features, their feedback and vote rounds,
the complete review catalog, and every export.

Exports
-------
simple     one row per round (aggregate vector list)
complete   one row per review with every field (complete vector list)
custom     chosen columns and catalog filters, for data science; also the
           file the built-in notebook opens
kit        a zip for other tools: custom CSV, JSON, notebook (.ipynb),
           pandas script (.py), SQLite database and a README
"""

import csv
import io
import json
import os
import sqlite3
import tempfile
import zipfile
from collections import Counter, defaultdict
from datetime import datetime

from . import store

STATUS_LABELS = {
    "launched": "Launched",
    "scheduled": "Scheduled",
    "held": "Held",
    "failed": "Failed",
}

# What the status date means for each status.
STATUS_DATE_LABELS = {
    "launched": "Launched on",
    "scheduled": "Scheduled for",
    "held": "Held since",
    "failed": "Failed on",
}

AGE_BUCKETS = (("under 7 days", 0, 6), ("7-30 days", 7, 30),
               ("31-90 days", 31, 90), ("over 90 days", 91, None))

# Every column of the complete vector list, in order.
REVIEW_COLUMNS = (
    ("review_id", "text", "Unique id of the review"),
    ("feature_id", "text", "Test feature id"),
    ("feature_name", "text", "Test feature name"),
    ("category", "text", "Edge case, frontier, expert, experimental, unique or new"),
    ("round", "integer", "Round number"),
    ("round_kind", "text", "feedback or vote"),
    ("reviewed_at", "datetime", "When the review was sent (UTC)"),
    ("date", "date", "Day the review was sent"),
    ("account_id", "text", "Pseudonymous account id"),
    ("signup_method", "text", "email, phone, google or web3"),
    ("account_age_days", "integer", "Account age in days when reviewing"),
    ("account_age", "text", "Account age bucket"),
    ("app_version", "text", "App version used"),
    ("rating", "integer", "Rating 1-5, blank in vote rounds"),
    ("vote", "text", "yes, no or abstain; blank in feedback rounds"),
    ("has_comment", "0/1", "1 if a comment was written"),
    ("comment_words", "integer", "Words in the comment"),
    ("comment", "text", "The comment"),
)
REVIEW_COLUMN_NAMES = tuple(c[0] for c in REVIEW_COLUMNS)

ROUND_COLUMNS = (
    "feature_id", "feature_name", "round", "round_kind", "opened_at",
    "closed_at", "invited", "reviewers", "response_rate", "reviews",
    "avg_rating", "rating_1", "rating_2", "rating_3", "rating_4", "rating_5",
    "yes", "no", "abstain", "yes_share", "decision",
)

ARCHIVE_COLUMNS = (
    "row", "archive_status", "status_date", "feature_id", "feature_name",
    "category", "stage", "rounds_done", "rounds_planned", "reviewers",
    "reviews", "avg_rating", "yes_share", "vote_threshold", "outcome",
    "outcome_date", "collectables", "last_activity", "app_version",
)


def _ratio(part, whole):
    return round(part / whole, 4) if whole else None


def _age_bucket(days):
    if days is None:
        return ""
    for label, low, high in AGE_BUCKETS:
        if days >= low and (high is None or days <= high):
            return label
    return ""


def _words(text):
    return len(text.split()) if text and text.strip() else 0


# ---- Reading -----------------------------------------------------------------

def _features(db):
    return [dict(r) for r in db.execute(
        "SELECT * FROM features ORDER BY created_at, feature_id")]


def _rounds(db, feature_id=None):
    sql = "SELECT * FROM feature_rounds"
    args = ()
    if feature_id:
        sql += " WHERE feature_id = ?"
        args = (feature_id,)
    rounds = defaultdict(list)
    for r in db.execute(sql + " ORDER BY feature_id, round", args):
        rounds[r["feature_id"]].append(dict(r))
    return rounds


def reviews(db, feature_id=None):
    """Complete review rows (every column of REVIEW_COLUMNS)."""
    sql = (
        "SELECT r.review_id, r.feature_id, f.name AS feature_name, f.category,"
        " r.round, fr.kind AS round_kind, r.at AS reviewed_at, r.account_id,"
        " a.method AS signup_method, a.created_at AS account_created,"
        " r.app_version, r.rating, r.vote, r.comment"
        " FROM feature_reviews r JOIN features f ON f.feature_id = r.feature_id"
        " LEFT JOIN feature_rounds fr ON fr.feature_id = r.feature_id"
        "  AND fr.round = r.round"
        " LEFT JOIN accounts a ON a.account_id = r.account_id")
    args = ()
    if feature_id:
        sql += " WHERE r.feature_id = ?"
        args = (feature_id,)
    out = []
    for r in db.execute(sql + " ORDER BY r.at, r.review_id", args):
        row = dict(r)
        created = row.pop("account_created")
        age = None
        if created:
            age = (datetime.fromisoformat(row["reviewed_at"]) -
                   datetime.fromisoformat(created)).days
        comment = row["comment"] or ""
        row.update({
            "date": row["reviewed_at"][:10],
            "account_age_days": age,
            "account_age": _age_bucket(age),
            "signup_method": row["signup_method"] or "",
            "has_comment": 1 if comment.strip() else 0,
            "comment_words": _words(comment),
            "comment": comment,
        })
        out.append({k: row.get(k) for k in REVIEW_COLUMN_NAMES})
    return out


def round_summaries(feature, rounds, review_rows):
    by_round = defaultdict(list)
    for r in review_rows:
        by_round[r["round"]].append(r)
    out = []
    for rd in rounds:
        rows = by_round.get(rd["round"], [])
        ratings = [r["rating"] for r in rows if r["rating"] is not None]
        votes = Counter(r["vote"] for r in rows if r["vote"])
        cast = votes["yes"] + votes["no"]
        reviewers = len({r["account_id"] for r in rows})
        mix = Counter(ratings)
        out.append({
            "feature_id": feature["feature_id"],
            "feature_name": feature["name"],
            "round": rd["round"],
            "round_kind": rd["kind"],
            "opened_at": rd["opened_at"],
            "closed_at": rd["closed_at"],
            "invited": rd["invited"],
            "reviewers": reviewers,
            "response_rate": _ratio(reviewers, rd["invited"]),
            "reviews": len(rows),
            "avg_rating": round(sum(ratings) / len(ratings), 2) if ratings else None,
            "rating_1": mix[1], "rating_2": mix[2], "rating_3": mix[3],
            "rating_4": mix[4], "rating_5": mix[5],
            "yes": votes["yes"], "no": votes["no"], "abstain": votes["abstain"],
            "yes_share": _ratio(votes["yes"], cast),
            "decision": rd["decision"],
        })
    return out


def _stage(feature, rounds):
    if feature["status"] == "scheduled" or not rounds:
        return "Not started"
    if feature["status"] == "held":
        return "On hold"
    if feature["status"] == "failed" and feature["outcome"] == "pending":
        return "Stopped"
    if feature["outcome"] != "pending":
        return "Decided"
    current = rounds[-1]
    if current["closed_at"] is None:
        if current["kind"] == "vote":
            return "Voting open"
        return "Feedback round %d open" % current["round"]
    return "Under review"


def archive(db):
    """The top level of the archive: one row per test feature."""
    features = _features(db)
    rounds = _rounds(db)
    all_reviews = defaultdict(list)
    for r in reviews(db):
        all_reviews[r["feature_id"]].append(r)
    collectables = dict(db.execute(
        "SELECT feature_id, COUNT(*) FROM collectables GROUP BY feature_id"
    ).fetchall())
    rows = []
    for n, f in enumerate(features, 1):
        frs = rounds.get(f["feature_id"], [])
        rv = all_reviews.get(f["feature_id"], [])
        summaries = round_summaries(f, frs, rv)
        ratings = [r["rating"] for r in rv if r["rating"] is not None]
        vote_rounds = [s for s in summaries if s["round_kind"] == "vote"]
        yes_share = vote_rounds[-1]["yes_share"] if vote_rounds else None
        activity = [f["status_date"], f["created_at"]] + \
            [r["reviewed_at"] for r in rv[-1:]] + \
            [x for s in frs for x in (s["opened_at"], s["closed_at"]) if x]
        rows.append({
            "row": n,
            "archive_status": f["status"],
            "status_date": f["status_date"][:10],
            "feature_id": f["feature_id"],
            "feature_name": f["name"],
            "category": f["category"],
            "description": f["description"],
            "stage": _stage(f, frs),
            "rounds_done": sum(1 for s in frs if s["closed_at"]),
            "rounds_planned": max(f["planned_rounds"], len(frs)),
            "reviewers": len({r["account_id"] for r in rv}),
            "reviews": len(rv),
            "avg_rating": round(sum(ratings) / len(ratings), 2) if ratings else None,
            "yes_share": yes_share,
            "vote_threshold": f["vote_threshold"],
            "outcome": f["outcome"],
            "outcome_date": (f["outcome_date"] or "")[:10],
            "collectables": collectables.get(f["feature_id"], 0),
            "last_activity": max(activity)[:10],
            "app_version": f["app_version"],
        })
    return rows


def summary(db):
    """Feature-testing figures for the overview page."""
    rows = archive(db)
    counts = Counter(r["archive_status"] for r in rows)
    open_rounds = db.execute(
        "SELECT COUNT(*) FROM feature_rounds WHERE closed_at IS NULL"
    ).fetchone()[0]
    rates = []
    for rd in db.execute(
            "SELECT fr.invited, COUNT(DISTINCT r.account_id) AS n"
            " FROM feature_rounds fr LEFT JOIN feature_reviews r"
            " ON r.feature_id = fr.feature_id AND r.round = fr.round"
            " WHERE fr.invited > 0 GROUP BY fr.feature_id, fr.round"):
        rates.append(rd["n"] / rd["invited"])
    shipped = [r for r in rows if r["outcome"] == "dedicated update"]
    last = max(shipped, key=lambda r: r["outcome_date"]) if shipped else None
    return {
        "total": len(rows),
        "by_status": {s: counts.get(s, 0) for s in store.FEATURE_STATUSES},
        "open_rounds": open_rounds,
        "avg_response_rate": round(sum(rates) / len(rates), 4) if rates else None,
        "passed_vote": sum(1 for r in rows if r["yes_share"] is not None
                           and r["yes_share"] >= r["vote_threshold"]),
        "dedicated_updates": len(shipped),
        "collectables": db.execute("SELECT COUNT(*) FROM collectables").fetchone()[0],
        "reviews": db.execute("SELECT COUNT(*) FROM feature_reviews").fetchone()[0],
        "last_shipped": {"feature_id": last["feature_id"],
                         "feature_name": last["feature_name"],
                         "date": last["outcome_date"]} if last else None,
    }


def detail(db, feature_id):
    """One archive data point: the feature, its rounds and every review."""
    row = next((r for r in archive(db) if r["feature_id"] == feature_id), None)
    if row is None:
        return None
    feature = dict(db.execute("SELECT * FROM features WHERE feature_id = ?",
                              (feature_id,)).fetchone())
    frs = _rounds(db, feature_id).get(feature_id, [])
    rv = reviews(db, feature_id)
    invited = max([r["invited"] for r in frs] or [0])
    return {
        "archive": row,
        "status_date_label": STATUS_DATE_LABELS[feature["status"]],
        "response_rate": _ratio(row["reviewers"], invited),
        "rounds": round_summaries(feature, frs, rv),
        "reviews": rv,
        "filters": filter_options(rv),
        "columns": [{"name": n, "type": t, "meaning": m}
                    for n, t, m in REVIEW_COLUMNS],
    }


def filter_options(review_rows):
    """Filter values found in the catalog, overall and per round, so each
    round only offers what its reviews contain."""
    def options(rows):
        dates = sorted(r["date"] for r in rows)
        return {
            "rating": sorted({r["rating"] for r in rows if r["rating"] is not None}),
            "vote": [v for v in store.VOTES if any(r["vote"] == v for r in rows)],
            "app_version": sorted({r["app_version"] for r in rows if r["app_version"]}),
            "signup_method": [m for m in store.SIGNUP_METHODS
                              if any(r["signup_method"] == m for r in rows)],
            "account_age": [b[0] for b in AGE_BUCKETS
                            if any(r["account_age"] == b[0] for r in rows)],
            "comment": [x for x, test in (("with", 1), ("without", 0))
                        if any(r["has_comment"] == test for r in rows)],
            "from": dates[0] if dates else None,
            "to": dates[-1] if dates else None,
            "count": len(rows),
        }

    by_round = defaultdict(list)
    for r in review_rows:
        by_round[r["round"]].append(r)
    return {"all": options(review_rows),
            "rounds": {str(k): options(v) for k, v in sorted(by_round.items())}}


FILTER_KEYS = ("round", "rating", "vote", "app_version", "signup_method",
               "account_age", "comment", "q", "from", "to")


def filter_reviews(review_rows, params):
    """Applies catalog filters. List filters take comma-separated values;
    'q' searches the comment, account id and review id."""
    def values(key):
        raw = params.get(key)
        if raw in (None, ""):
            return None
        if isinstance(raw, (list, tuple)):
            raw = ",".join(str(x) for x in raw)
        return {v.strip() for v in str(raw).split(",") if v.strip()}

    rounds = values("round")
    ratings = values("rating")
    votes = values("vote")
    versions = values("app_version")
    methods = values("signup_method")
    ages = values("account_age")
    comment = (params.get("comment") or "").strip()
    query = (params.get("q") or "").strip().lower()
    start = (params.get("from") or "").strip()
    end = (params.get("to") or "").strip()
    out = []
    for r in review_rows:
        if rounds and str(r["round"]) not in rounds:
            continue
        if ratings and str(r["rating"]) not in ratings:
            continue
        if votes and (r["vote"] or "") not in votes:
            continue
        if versions and r["app_version"] not in versions:
            continue
        if methods and r["signup_method"] not in methods:
            continue
        if ages and r["account_age"] not in ages:
            continue
        if comment == "with" and not r["has_comment"]:
            continue
        if comment == "without" and r["has_comment"]:
            continue
        if start and r["date"] < start:
            continue
        if end and r["date"] > end:
            continue
        if query and query not in ("%s %s %s" % (
                r["comment"], r["account_id"] or "", r["review_id"])).lower():
            continue
        out.append(r)
    return out


def pick_columns(raw):
    if not raw:
        return list(REVIEW_COLUMN_NAMES)
    wanted = [c.strip() for c in str(raw).split(",") if c.strip()]
    unknown = [c for c in wanted if c not in REVIEW_COLUMN_NAMES]
    if unknown:
        raise ValueError("unknown columns: " + ", ".join(unknown))
    return [c for c in REVIEW_COLUMN_NAMES if c in wanted]


# ---- Writing -------------------------------------------------------------------

def to_csv(rows, columns):
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\r\n")
    writer.writerow(columns)
    for row in rows:
        writer.writerow(["" if row.get(c) is None else row.get(c) for c in columns])
    return buffer.getvalue()


def to_json(rows, columns, meta):
    return json.dumps({**meta, "columns": list(columns),
                       "rows": [{c: row.get(c) for c in columns} for row in rows]},
                      indent=2, ensure_ascii=False)


def archive_export(db, kind, fmt):
    """Archive-level downloads: simple = one row per feature; complete =
    every review of every feature."""
    if kind == "simple":
        rows, columns = archive(db), ARCHIVE_COLUMNS
    elif kind == "complete":
        rows, columns = reviews(db), REVIEW_COLUMN_NAMES
    else:
        raise ValueError("kind must be simple or complete")
    name = "eventlens-feature-archive-%s" % kind
    meta = {"format": "eventlens-feature-archive", "kind": kind,
            "exported_at": store.iso(datetime.now())}
    if fmt == "csv":
        return name + ".csv", "text/csv", to_csv(rows, columns).encode("utf-8")
    if fmt == "json":
        return name + ".json", "application/json", \
            to_json(rows, columns, meta).encode("utf-8")
    raise ValueError("format must be csv or json")


def feature_export(db, feature_id, kind, fmt, params):
    """Downloads for one feature. Returns (file name, type, bytes)."""
    data = detail(db, feature_id)
    if data is None:
        raise KeyError(feature_id)
    base = "eventlens-%s-%s" % (feature_id.lower(), kind)
    meta = {"format": "eventlens-feature-reviews", "feature_id": feature_id,
            "feature_name": data["archive"]["feature_name"], "kind": kind,
            "exported_at": store.iso(datetime.now())}
    if kind == "simple":
        rows, columns = data["rounds"], ROUND_COLUMNS
    elif kind == "complete":
        rows, columns = data["reviews"], REVIEW_COLUMN_NAMES
    elif kind == "custom":
        columns = pick_columns(params.get("columns"))
        rows = filter_reviews(data["reviews"], params)
        meta["filters"] = {k: params[k] for k in FILTER_KEYS if params.get(k)}
    else:
        raise ValueError("kind must be simple, complete or custom")

    if fmt == "csv":
        return base + ".csv", "text/csv", to_csv(rows, columns).encode("utf-8")
    if fmt == "json":
        return base + ".json", "application/json", \
            to_json(rows, columns, meta).encode("utf-8")
    if fmt == "kit":
        return base + "-analysis-kit.zip", "application/zip", \
            analysis_kit(data, rows, columns, meta, base)
    raise ValueError("format must be csv, json or kit")


def notebook(feature, csv_name, columns, filters):
    """A fresh Jupyter notebook that loads [csv_name] with pandas."""
    def md(text):
        return {"cell_type": "markdown", "metadata": {}, "source": text}

    def code(text):
        return {"cell_type": "code", "metadata": {}, "execution_count": None,
                "outputs": [], "source": text}

    dates = [c for c in ("reviewed_at",) if c in columns]
    load = "import pandas as pd\n\nreviews = pd.read_csv(%r%s)\nreviews.head()" % (
        csv_name, ", parse_dates=%r" % dates if dates else "")
    cells = [
        md("# %s (%s): review analysis\n\n"
           "Generated by the EventLens owner dashboard. This notebook starts "
           "fresh every time it opens; to keep your changes, use "
           "**File → Download**.\n\n"
           "Rows: one per review. Filters: %s." % (
               feature["feature_name"], feature["feature_id"],
               ", ".join("%s = %s" % kv for kv in sorted(filters.items())) or "none")),
        code(load),
        code("reviews.describe(include='all').T"),
    ]
    if "round" in columns and "rating" in columns:
        cells.append(code(
            "# Reviews and average rating per round\n"
            "reviews.groupby('round').agg(reviews=('rating', 'size'),"
            " avg_rating=('rating', 'mean'))"))
    if "rating" in columns:
        cells.append(code(
            "# Rating mix\n"
            "reviews['rating'].dropna().astype(int).value_counts().sort_index()"
            ".plot(kind='bar', title='Ratings (1-5)')"))
    if "vote" in columns:
        cells.append(code(
            "# Vote share (the dedicated-update bar is %d%% yes)\n"
            "votes = reviews['vote'].dropna()\n"
            "votes[votes != 'abstain'].value_counts(normalize=True)"
            % round(feature["vote_threshold"] * 100)))
    if "signup_method" in columns and "rating" in columns:
        cells.append(code(
            "# Average rating by sign-up method\n"
            "reviews.groupby('signup_method')['rating'].mean().sort_values()"))
    if "comment" in columns:
        cells.append(code(
            "# Most common words in comments\n"
            "words = reviews['comment'].fillna('').str.lower()"
            ".str.findall(r\"[a-z']{4,}\").explode()\n"
            "words.value_counts().head(20)"))
    cells.append(md("Columns are described in the dashboard's column guide "
                    "and in README.txt of the analysis kit."))
    return {
        "cells": cells,
        "metadata": {
            "kernelspec": {"name": "python", "display_name": "Python (Pyodide)",
                           "language": "python"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


def analysis_kit(data, rows, columns, meta, base):
    """A zip for tools other than the built-in notebook."""
    feature = data["archive"]
    csv_name = base + ".csv"
    nb = notebook(feature, csv_name, columns, meta.get("filters", {}))
    nb["metadata"]["kernelspec"] = {"name": "python3", "display_name": "Python 3",
                                    "language": "python"}
    script = (
        '"""%s (%s): review analysis with pandas.\n\n'
        "Run next to %s:  python %s.py\n\"\"\"\n\n"
        "import pandas as pd\n\n"
        "reviews = pd.read_csv(%r)\n"
        "print(reviews.head())\n"
        "print(reviews.describe(include='all').T)\n" % (
            feature["feature_name"], feature["feature_id"], csv_name, base,
            csv_name))
    if "round" in columns and "rating" in columns:
        script += "print(reviews.groupby('round')['rating'].agg(['size', 'mean']))\n"
    if "vote" in columns:
        script += "print(reviews['vote'].value_counts(normalize=True))\n"

    with tempfile.TemporaryDirectory() as folder:
        db_path = os.path.join(folder, "kit.sqlite")
        kit_db = sqlite3.connect(db_path)
        kit_db.execute("CREATE TABLE reviews (%s)" % ", ".join(
            '"%s" %s' % (c, {"integer": "INTEGER", "0/1": "INTEGER"}.get(
                dict((n, t) for n, t, _ in REVIEW_COLUMNS)[c], "TEXT"))
            for c in columns))
        kit_db.executemany("INSERT INTO reviews VALUES (%s)" % ",".join(
            "?" * len(columns)), [[r.get(c) for c in columns] for r in rows])
        kit_db.execute("CREATE TABLE rounds (%s)" % ", ".join(
            '"%s"' % c for c in ROUND_COLUMNS))
        kit_db.executemany("INSERT INTO rounds VALUES (%s)" % ",".join(
            "?" * len(ROUND_COLUMNS)),
            [[r.get(c) for c in ROUND_COLUMNS] for r in data["rounds"]])
        kit_db.commit()
        kit_db.close()
        with open(db_path, "rb") as handle:
            db_bytes = handle.read()

    guide = ["%s (%s): analysis kit" % (feature["feature_name"], feature["feature_id"]),
             "", "Files",
             "  %s            the reviews (UTF-8, comma-separated)" % csv_name,
             "  %s.json           the same rows as JSON, with the filters used" % base,
             "  %s.ipynb          a starter Jupyter notebook" % base,
             "  %s.py             the same start as a pandas script" % base,
             "  %s.sqlite         tables 'reviews' and 'rounds' (SQLite)" % base,
             "", "Columns"]
    types = dict((n, (t, m)) for n, t, m in REVIEW_COLUMNS)
    guide += ["  %-18s %-9s %s" % (c, types[c][0], types[c][1]) for c in columns]
    guide += ["", "Filters: " + (", ".join("%s = %s" % kv for kv in sorted(
        meta.get("filters", {}).items())) or "none"),
              "Exported: " + meta["exported_at"], ""]

    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as kit:
        kit.writestr(csv_name, to_csv(rows, columns))
        kit.writestr(base + ".json", to_json(rows, columns, meta))
        kit.writestr(base + ".ipynb", json.dumps(nb, indent=1))
        kit.writestr(base + ".py", script)
        kit.writestr(base + ".sqlite", db_bytes)
        kit.writestr("README.txt", "\n".join(guide))
    return out.getvalue()
