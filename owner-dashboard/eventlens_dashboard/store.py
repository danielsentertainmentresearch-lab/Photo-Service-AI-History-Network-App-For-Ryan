"""The metrics database (SQLite) and every measure the dashboard shows.

Tables
------
installs   one row per app install (before any account exists)
accounts   one row per created account, linked to its install
activity   things people did, by install and (once signed up) account
sessions   app sessions with their length and whether they crashed
crashes    crash reports, linked to a session
features         test features (the feature-test archive)
feature_rounds   feedback and vote rounds of each test feature
feature_reviews  individual reviews (the complete review catalog)
collectables     recognition linked to a shipped feature, per account

Times are stored as ISO 8601 UTC strings ("2026-10-03T14:05:00").
"""

import json
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

SCHEMA = """
CREATE TABLE IF NOT EXISTS installs (
  install_id  TEXT PRIMARY KEY,
  first_seen  TEXT NOT NULL,
  platform    TEXT NOT NULL DEFAULT 'android',
  app_version TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS accounts (
  account_id  TEXT PRIMARY KEY,
  install_id  TEXT,
  created_at  TEXT NOT NULL,
  method      TEXT NOT NULL,
  deleted_at  TEXT
);
CREATE TABLE IF NOT EXISTS activity (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id  TEXT,
  account_id  TEXT,
  at          TEXT NOT NULL,
  kind        TEXT NOT NULL,
  value       REAL NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS sessions (
  session_id  TEXT PRIMARY KEY,
  install_id  TEXT,
  account_id  TEXT,
  started_at  TEXT NOT NULL,
  minutes     REAL NOT NULL DEFAULT 0,
  crashed     INTEGER NOT NULL DEFAULT 0,
  app_version TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS crashes (
  crash_id    TEXT PRIMARY KEY,
  session_id  TEXT,
  account_id  TEXT,
  at          TEXT NOT NULL,
  app_version TEXT NOT NULL DEFAULT '',
  signature   TEXT NOT NULL,
  message     TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS features (
  feature_id     TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  category       TEXT NOT NULL,
  description    TEXT NOT NULL DEFAULT '',
  status         TEXT NOT NULL,
  status_date    TEXT NOT NULL,
  created_at     TEXT NOT NULL,
  app_version    TEXT NOT NULL DEFAULT '',
  planned_rounds INTEGER NOT NULL DEFAULT 1,
  outcome        TEXT NOT NULL DEFAULT 'pending',
  outcome_date   TEXT,
  vote_threshold REAL NOT NULL DEFAULT 0.9
);
CREATE TABLE IF NOT EXISTS feature_rounds (
  feature_id  TEXT NOT NULL,
  round       INTEGER NOT NULL,
  kind        TEXT NOT NULL,
  opened_at   TEXT NOT NULL,
  closed_at   TEXT,
  invited     INTEGER NOT NULL DEFAULT 0,
  decision    TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (feature_id, round)
);
CREATE TABLE IF NOT EXISTS feature_reviews (
  review_id   TEXT PRIMARY KEY,
  feature_id  TEXT NOT NULL,
  round       INTEGER NOT NULL,
  account_id  TEXT,
  at          TEXT NOT NULL,
  rating      INTEGER,
  vote        TEXT,
  comment     TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS collectables (
  feature_id  TEXT NOT NULL,
  account_id  TEXT NOT NULL,
  issued_at   TEXT NOT NULL,
  PRIMARY KEY (feature_id, account_id)
);
CREATE INDEX IF NOT EXISTS reviews_feature ON feature_reviews(feature_id, round);
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS activity_at ON activity(at);
CREATE INDEX IF NOT EXISTS activity_kind ON activity(kind, account_id);
CREATE INDEX IF NOT EXISTS sessions_at ON sessions(started_at);
"""

# Things the app can report. Anything else is rejected at ingest.
ACTIVITY_KINDS = (
    "tutorial_started",
    "tutorial_finished",
    "signup_started",
    "signup_completed",
    "app_open",
    "event_created",
    "event_described",
    "photo_added",
    "graph_unlocked",
    "export_unlocked",
    "export",
    "weather_lookup",
    "ring_unlocked",
    "ad_watched",
    "memory_saved",
    "mind_map_opened",
    "mind_map_centered",
    "free_write_saved",
    "free_write_labelled",
    "label_confirmed",
    "label_rejected",
    "label_relabelled",
    "ai_allowance_reached",
    "ai_topup",
    "ai_question_answered",
    "ai_question_skipped",
    "insight_peek_opened",
    "insight_pass_bought",
    "learning_page_opened",
)

SIGNUP_METHODS = ("email", "phone", "google", "web3")

# Feature-test archive vocabulary.
FEATURE_STATUSES = ("launched", "scheduled", "held", "failed")
FEATURE_CATEGORIES = ("edge case", "frontier", "expert", "experimental",
                      "unique", "new")
FEATURE_OUTCOMES = ("pending", "dedicated update", "next major version",
                    "holiday or promotional event", "back to testing",
                    "retired")
ROUND_KINDS = ("feedback", "vote")
VOTES = ("yes", "no", "abstain")

# Reach vs utilization: each step is a milestone an install can reach.
REACH_STEPS = (
    ("installs", "Installed the app"),
    ("tutorial_finished", "Finished the tutorial"),
    ("signup_completed", "Created an account"),
    ("event_created", "Recorded a first event"),
    ("event_described", "Got a first AI account"),
    ("graph_unlocked", "Unlocked the timeline graph"),
    ("export_unlocked", "Reached 100 events"),
)

SIGNUP_STEPS = (
    ("tutorial_started", "Opened the tutorial"),
    ("tutorial_finished", "Finished the tutorial"),
    ("signup_started", "Started sign-up"),
    ("signup_completed", "Completed sign-up"),
)

FEATURES = (
    ("event_created", "Events recorded"),
    ("event_described", "AI accounts written"),
    ("photo_added", "Photos added"),
    ("memory_saved", "Memories saved"),
    ("free_write_saved", "Free writes saved"),
    ("free_write_labelled", "Free writes labelled"),
    ("label_confirmed", "Labels confirmed"),
    ("label_rejected", "Labels marked not right"),
    ("label_relabelled", "Re-labels asked for"),
    ("ai_allowance_reached", "Daily AI allowance used up"),
    ("ai_topup", "AI allowance top-ups from ads"),
    ("ai_question_answered", "AI who/where questions answered"),
    ("ai_question_skipped", "AI who/where questions skipped"),
    ("insight_peek_opened", "Insight sneak peeks opened with videos"),
    ("insight_pass_bought", "$1 insight passes bought"),
    ("learning_page_opened", "\"What the AI is learning\" opened"),
    ("mind_map_opened", "Mind map opened"),
    ("mind_map_centered", "Mind map ideas centred on"),
    ("weather_lookup", "Weather lookups"),
    ("ring_unlocked", "Ring colours unlocked"),
    ("ad_watched", "Rewarded videos watched"),
    ("export", "Exports made"),
)

# Share of reviewed free-write labels that people mark as not right. At or
# above WATCH the labelling instructions deserve a look; at or above ALERT
# they need changing.
LABEL_REJECTION_WATCH = 0.10
LABEL_REJECTION_ALERT = 0.20

DEPTH_BUCKETS = ((0, 0, "0 events"), (1, 4, "1-4"), (5, 19, "5-19"),
                 (20, 99, "20-99"), (100, None, "100+"))

WINDOWS = {"7": 7, "30": 30, "90": 90, "365": 365, "all": None}


def connect(path):
    db = sqlite3.connect(path, check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.executescript(SCHEMA)
    return db


def iso(moment):
    return moment.replace(microsecond=0).isoformat()


def parse_time(text):
    """Accepts ISO 8601 with or without a zone; returns naive UTC."""
    moment = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    if moment.tzinfo is not None:
        moment = (moment - moment.utcoffset()).replace(tzinfo=None)
    return moment


def set_meta(db, key, value):
    db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
               (key, json.dumps(value)))


def get_meta(db, key, default=None):
    row = db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    return json.loads(row["value"]) if row else default


def clear(db):
    for table in ("installs", "accounts", "activity", "sessions", "crashes",
                  "features", "feature_rounds", "feature_reviews",
                  "collectables", "meta"):
        db.execute("DELETE FROM " + table)
    db.commit()


# ---- Ingest -----------------------------------------------------------------

class IngestError(ValueError):
    """A record the dashboard can't accept; the message says why."""


def _need(record, *keys):
    for key in keys:
        if record.get(key) in (None, ""):
            raise IngestError("'%s' is missing in a %s record"
                              % (key, record.get("type", "?")))


def _one_of(record, key, allowed):
    if record.get(key) not in allowed:
        raise IngestError("unknown %s '%s'" % (key, record.get(key)))


def ingest(db, records):
    """Stores a batch of records sent by the app. All or nothing: one bad
    record rejects the batch, so a retry never stores half of it."""
    if not isinstance(records, list):
        raise IngestError("'records' must be a list")
    if len(records) > 5000:
        raise IngestError("send at most 5000 records per request")
    rows = []
    for record in records:
        if not isinstance(record, dict):
            raise IngestError("each record must be an object")
        kind = record.get("type")
        try:
            if kind == "install":
                _need(record, "install_id", "at")
                rows.append((
                    "INSERT OR IGNORE INTO installs VALUES (?, ?, ?, ?)",
                    (record["install_id"], iso(parse_time(record["at"])),
                     record.get("platform", "android"),
                     record.get("app_version", ""))))
            elif kind == "account":
                _need(record, "account_id", "at", "method")
                if record["method"] not in SIGNUP_METHODS:
                    raise IngestError("unknown sign-up method '%s'"
                                      % record["method"])
                rows.append((
                    "INSERT OR IGNORE INTO accounts VALUES (?, ?, ?, ?, NULL)",
                    (record["account_id"], record.get("install_id"),
                     iso(parse_time(record["at"])), record["method"])))
            elif kind == "account_deleted":
                _need(record, "account_id", "at")
                rows.append((
                    "UPDATE accounts SET deleted_at = ? WHERE account_id = ?",
                    (iso(parse_time(record["at"])), record["account_id"])))
            elif kind == "activity":
                _need(record, "kind", "at")
                if record["kind"] not in ACTIVITY_KINDS:
                    raise IngestError("unknown activity '%s'" % record["kind"])
                if not (record.get("install_id") or record.get("account_id")):
                    raise IngestError("activity needs install_id or account_id")
                rows.append((
                    "INSERT INTO activity(install_id, account_id, at, kind,"
                    " value) VALUES (?, ?, ?, ?, ?)",
                    (record.get("install_id"), record.get("account_id"),
                     iso(parse_time(record["at"])), record["kind"],
                     float(record.get("value", 1)))))
            elif kind == "session":
                _need(record, "session_id", "at")
                rows.append((
                    "INSERT OR REPLACE INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (record["session_id"], record.get("install_id"),
                     record.get("account_id"), iso(parse_time(record["at"])),
                     max(0.0, float(record.get("minutes", 0))),
                     1 if record.get("crashed") else 0,
                     record.get("app_version", ""))))
            elif kind == "crash":
                _need(record, "crash_id", "at", "signature")
                rows.append((
                    "INSERT OR IGNORE INTO crashes VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (record["crash_id"], record.get("session_id"),
                     record.get("account_id"), iso(parse_time(record["at"])),
                     record.get("app_version", ""), record["signature"][:300],
                     str(record.get("message", ""))[:2000])))
            elif kind == "feature":
                _need(record, "feature_id", "name", "category", "status",
                      "status_date", "at")
                _one_of(record, "category", FEATURE_CATEGORIES)
                _one_of(record, "status", FEATURE_STATUSES)
                outcome = record.get("outcome", "pending")
                if outcome not in FEATURE_OUTCOMES:
                    raise IngestError("unknown outcome '%s'" % outcome)
                rows.append((
                    "INSERT OR REPLACE INTO features VALUES"
                    " (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (record["feature_id"], record["name"], record["category"],
                     record.get("description", ""), record["status"],
                     iso(parse_time(record["status_date"])),
                     iso(parse_time(record["at"])),
                     record.get("app_version", ""),
                     max(1, int(record.get("planned_rounds", 1))), outcome,
                     iso(parse_time(record["outcome_date"]))
                     if record.get("outcome_date") else None,
                     float(record.get("vote_threshold", 0.9)))))
            elif kind == "feature_round":
                _need(record, "feature_id", "round", "kind", "opened_at")
                _one_of(record, "kind", ROUND_KINDS)
                rows.append((
                    "INSERT OR REPLACE INTO feature_rounds VALUES"
                    " (?, ?, ?, ?, ?, ?, ?)",
                    (record["feature_id"], int(record["round"]),
                     record["kind"], iso(parse_time(record["opened_at"])),
                     iso(parse_time(record["closed_at"]))
                     if record.get("closed_at") else None,
                     max(0, int(record.get("invited", 0))),
                     str(record.get("decision", ""))[:200])))
            elif kind == "feature_review":
                _need(record, "review_id", "feature_id", "round", "at")
                rating = record.get("rating")
                if rating is not None and int(rating) not in (1, 2, 3, 4, 5):
                    raise IngestError("rating must be 1 to 5")
                vote = record.get("vote")
                if vote is not None and vote not in VOTES:
                    raise IngestError("vote must be yes, no or abstain")
                if rating is None and vote is None:
                    raise IngestError("a review needs a rating or a vote")
                rows.append((
                    "INSERT OR REPLACE INTO feature_reviews VALUES"
                    " (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (record["review_id"], record["feature_id"],
                     int(record["round"]), record.get("account_id"),
                     iso(parse_time(record["at"])),
                     int(rating) if rating is not None else None, vote,
                     str(record.get("comment", ""))[:4000],
                     record.get("app_version", ""))))
            elif kind == "collectable":
                _need(record, "feature_id", "account_id", "at")
                rows.append((
                    "INSERT OR IGNORE INTO collectables VALUES (?, ?, ?)",
                    (record["feature_id"], record["account_id"],
                     iso(parse_time(record["at"])))))
            else:
                raise IngestError("unknown record type '%s'" % kind)
        except (TypeError, ValueError) as error:
            if isinstance(error, IngestError):
                raise
            raise IngestError("a %s record has a bad value: %s"
                              % (kind, error))
    with db:
        for sql, params in rows:
            db.execute(sql, params)
    return len(rows)


# ---- Measures -----------------------------------------------------------------

def _ratio(part, whole):
    return round(part / whole, 4) if whole else 0.0


def as_of(db):
    """The dashboard's 'today': the last recorded moment, or now."""
    row = db.execute(
        "SELECT MAX(m) AS m FROM (SELECT MAX(at) AS m FROM activity"
        " UNION ALL SELECT MAX(started_at) FROM sessions"
        " UNION ALL SELECT MAX(created_at) FROM accounts)").fetchone()
    if row and row["m"]:
        return datetime.fromisoformat(row["m"])
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def metrics(db, window="30", now=None):
    """Everything the dashboard shows, for the last [window] days."""
    if window not in WINDOWS:
        raise ValueError("window must be one of " + ", ".join(WINDOWS))
    now = now or as_of(db)
    days = WINDOWS[window]
    end_day = now.date()
    start = None if days is None else datetime.combine(
        end_day - timedelta(days=days - 1), datetime.min.time())
    since = iso(start) if start else "0000"

    accounts = db.execute(
        "SELECT account_id, install_id, created_at, method, deleted_at"
        " FROM accounts").fetchall()
    total_accounts = len(accounts)
    live_accounts = [a for a in accounts if not a["deleted_at"]]
    new_accounts = [a for a in accounts if a["created_at"] >= since]

    active_rows = db.execute(
        "SELECT DISTINCT account_id FROM sessions WHERE account_id IS NOT NULL"
        " AND started_at >= ?", (since,)).fetchall()
    active = {r["account_id"] for r in active_rows}

    def active_between(first, last):
        rows = db.execute(
            "SELECT DISTINCT account_id FROM sessions WHERE account_id IS NOT"
            " NULL AND started_at >= ? AND started_at < ?",
            (iso(first), iso(last))).fetchall()
        return len(rows)

    day_start = datetime.combine(end_day, datetime.min.time())
    dau = active_between(day_start, day_start + timedelta(days=1))
    wau = active_between(day_start - timedelta(days=6), day_start + timedelta(days=1))
    mau = active_between(day_start - timedelta(days=29), day_start + timedelta(days=1))

    sessions = db.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(minutes), 0) AS minutes,"
        " COALESCE(SUM(crashed), 0) AS crashed FROM sessions"
        " WHERE started_at >= ?", (since,)).fetchone()
    session_minutes = [r["minutes"] for r in db.execute(
        "SELECT minutes FROM sessions WHERE started_at >= ? ORDER BY minutes",
        (since,)).fetchall()]
    median_minutes = (session_minutes[len(session_minutes) // 2]
                      if session_minutes else 0)

    summary = {
        "accounts_total": total_accounts,
        "accounts_live": len(live_accounts),
        "accounts_new": len(new_accounts),
        "accounts_active": len(active),
        "utilization_rate": _ratio(len(active & {a["account_id"] for a in live_accounts}),
                                   len(live_accounts)),
        "dau": dau,
        "wau": wau,
        "mau": mau,
        "stickiness": _ratio(dau, mau),
        "sessions": sessions["n"],
        "sessions_per_active": round(sessions["n"] / len(active), 2) if active else 0,
        "median_session_minutes": round(median_minutes, 1),
        "crash_free_sessions": round(1 - _ratio(sessions["crashed"], sessions["n"]), 4)
        if sessions["n"] else 1.0,
    }

    # Reach vs utilization, for installs first seen in the window.
    installs = {r["install_id"] for r in db.execute(
        "SELECT install_id FROM installs WHERE first_seen >= ?", (since,))}
    account_install = {a["account_id"]: a["install_id"] for a in accounts}
    reached = defaultdict(set)
    for row in db.execute(
            "SELECT DISTINCT kind, install_id, account_id FROM activity"):
        install = row["install_id"] or account_install.get(row["account_id"])
        if install in installs:
            reached[row["kind"]].add(install)
    for a in accounts:
        if a["install_id"] in installs:
            reached["signup_completed"].add(a["install_id"])
    reach = []
    previous = len(installs)
    for key, label in REACH_STEPS:
        count = len(installs) if key == "installs" else len(reached[key])
        reach.append({
            "key": key, "label": label, "count": count,
            "of_installs": _ratio(count, len(installs)),
            "from_previous": _ratio(count, previous),
        })
        previous = count

    signup = []
    previous = None
    for key, label in SIGNUP_STEPS:
        count = len(reached[key])
        signup.append({
            "key": key, "label": label, "count": count,
            "from_previous": _ratio(count, previous) if previous is not None else 1.0,
        })
        previous = count
    methods = Counter(a["method"] for a in new_accounts)
    signup_methods = [{"method": m, "count": methods.get(m, 0),
                       "share": _ratio(methods.get(m, 0), len(new_accounts))}
                      for m in SIGNUP_METHODS]

    # Daily new and active accounts.
    first_day = (start.date() if start else
                 min([datetime.fromisoformat(a["created_at"]).date()
                      for a in accounts] or [end_day]))
    span = (end_day - first_day).days + 1
    step = 1 if span <= 120 else 7
    new_by_day = Counter(a["created_at"][:10] for a in accounts)
    active_by_day = defaultdict(set)
    for row in db.execute(
            "SELECT substr(started_at, 1, 10) AS d, account_id FROM sessions"
            " WHERE account_id IS NOT NULL AND started_at >= ?", (iso(
                datetime.combine(first_day, datetime.min.time())),)):
        active_by_day[row["d"]].add(row["account_id"])
    series = []
    day = first_day
    while day <= end_day:
        bucket = [day + timedelta(days=i) for i in range(step) if day + timedelta(days=i) <= end_day]
        keys = [d.isoformat() for d in bucket]
        series.append({
            "date": keys[0],
            "new": sum(new_by_day.get(k, 0) for k in keys),
            "active": len(set().union(*[active_by_day.get(k, set()) for k in keys])),
        })
        day += timedelta(days=step)

    # Weekly retention: accounts by sign-up week, share active N weeks later.
    sessions_by_account = defaultdict(set)
    for row in db.execute(
            "SELECT account_id, substr(started_at, 1, 10) AS d FROM sessions"
            " WHERE account_id IS NOT NULL"):
        sessions_by_account[row["account_id"]].add(row["d"])
    cohorts = defaultdict(list)
    for a in accounts:
        created = datetime.fromisoformat(a["created_at"]).date()
        week = created - timedelta(days=created.weekday())
        cohorts[week].append((a["account_id"], created))
    retention = []
    for week in sorted(cohorts)[-8:]:
        members = cohorts[week]
        row = {"week": week.isoformat(), "size": len(members), "weeks": []}
        for n in range(1, 7):
            first = week + timedelta(days=7 * n)
            last = first + timedelta(days=6)
            if last > end_day:
                # That week isn't over yet, so it would understate.
                row["weeks"].append(None)
                continue
            kept = 0
            for account_id, _ in members:
                days_active = sessions_by_account.get(account_id, ())
                if any(first.isoformat() <= d <= last.isoformat() for d in days_active):
                    kept += 1
            row["weeks"].append(_ratio(kept, len(members)))
        retention.append(row)

    # Utilization depth: events recorded per account, all time.
    events_per_account = Counter()
    for row in db.execute(
            "SELECT account_id, SUM(value) AS n FROM activity WHERE kind ="
            " 'event_created' AND account_id IS NOT NULL GROUP BY account_id"):
        events_per_account[row["account_id"]] = int(row["n"])
    depth = []
    for low, high, label in DEPTH_BUCKETS:
        count = sum(1 for a in live_accounts
                    if events_per_account.get(a["account_id"], 0) >= low and
                    (high is None or events_per_account.get(a["account_id"], 0) <= high))
        depth.append({"label": label, "count": count,
                      "share": _ratio(count, len(live_accounts))})

    # Feature use in the window.
    feature_rows = {r["kind"]: r for r in db.execute(
        "SELECT kind, SUM(value) AS total, COUNT(DISTINCT account_id) AS people"
        " FROM activity WHERE at >= ? GROUP BY kind", (since,))}
    features = []
    for key, label in FEATURES:
        row = feature_rows.get(key)
        people = row["people"] if row else 0
        features.append({
            "key": key, "label": label,
            "total": int(row["total"]) if row else 0,
            "accounts": people,
            "share_of_active": _ratio(people, len(active)),
        })

    # Free-write label quality: how people judge the AI's labels.
    use = {f["key"]: f["total"] for f in features}
    reviewed = use["label_confirmed"] + use["label_rejected"]
    labels = {
        "labelled": use["free_write_labelled"],
        "confirmed": use["label_confirmed"],
        "rejected": use["label_rejected"],
        "relabelled": use["label_relabelled"],
        "reviewed": reviewed,
        "rejection_rate": (round(use["label_rejected"] / reviewed, 4)
                           if reviewed else None),
        "watch": LABEL_REJECTION_WATCH,
        "alert": LABEL_REJECTION_ALERT,
    }

    # Crashes.
    by_version = []
    for row in db.execute(
            "SELECT app_version, COUNT(*) AS n, SUM(crashed) AS c FROM sessions"
            " WHERE started_at >= ? GROUP BY app_version ORDER BY app_version",
            (since,)):
        by_version.append({
            "version": row["app_version"] or "unknown",
            "sessions": row["n"], "crashes": row["c"] or 0,
            "crash_free": round(1 - _ratio(row["c"] or 0, row["n"]), 4),
        })
    top_crashes = [dict(r) for r in db.execute(
        "SELECT signature, COUNT(*) AS count, COUNT(DISTINCT account_id) AS"
        " accounts, MAX(at) AS last_seen, MAX(app_version) AS latest_version"
        " FROM crashes WHERE at >= ? GROUP BY signature ORDER BY count DESC"
        " LIMIT 8", (since,))]

    # Lifetime totals.
    totals = {r["kind"]: int(r["n"] or 0) for r in db.execute(
        "SELECT kind, SUM(value) AS n FROM activity GROUP BY kind")}
    lifetime_sessions = db.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(minutes), 0) AS m FROM sessions"
    ).fetchone()
    lifetime = {
        "installs": db.execute("SELECT COUNT(*) FROM installs").fetchone()[0],
        "accounts": total_accounts,
        "accounts_deleted": total_accounts - len(live_accounts),
        "events": totals.get("event_created", 0),
        "ai_accounts": totals.get("event_described", 0),
        "photos": totals.get("photo_added", 0),
        "sessions": lifetime_sessions["n"],
        "hours_in_app": round(lifetime_sessions["m"] / 60, 1),
        "rewarded_videos": totals.get("ad_watched", 0),
    }

    # Feature testing: reviews in the window, and the archive's state.
    from . import features as feature_archive
    review_rows = db.execute(
        "SELECT account_id FROM feature_reviews WHERE at >= ?", (since,)
    ).fetchall()
    reviewers = {r["account_id"] for r in review_rows if r["account_id"]}
    features.append({
        "key": "feature_review", "label": "Feature test reviews",
        "total": len(review_rows), "accounts": len(reviewers),
        "share_of_active": _ratio(len(reviewers & active), len(active)),
    })
    testing = feature_archive.summary(db)
    lifetime["feature_reviews"] = testing["reviews"]
    lifetime["collectables"] = testing["collectables"]

    return {
        "window": window,
        "as_of": iso(now),
        "feature_testing": testing,
        "from": first_day.isoformat(),
        "source": get_meta(db, "source", "app"),
        "summary": summary,
        "reach": reach,
        "signup": signup,
        "signup_methods": signup_methods,
        "daily": series,
        "daily_step_days": step,
        "retention": retention,
        "depth": depth,
        "features": features,
        "labels": labels,
        "crashes": {"by_version": by_version, "top": top_crashes},
        "lifetime": lifetime,
    }
