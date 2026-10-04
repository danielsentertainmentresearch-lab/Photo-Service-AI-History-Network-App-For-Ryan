"""Synthetic example data, so the dashboard can be reviewed before the app
sends real metrics. Always labelled "Demo data" in the dashboard.

The same seed always produces the same data, so screenshots and tests are
repeatable.
"""

import random
from datetime import datetime, timedelta

from . import store

VERSIONS = (
    (datetime(2026, 4, 1), "1.0.0"),
    (datetime(2026, 6, 15), "1.0.1"),
    (datetime(2026, 8, 20), "1.1.0"),
)

CRASHES = (
    ("SqfliteException: database is locked (event_repository.dart)", 0.30),
    ("PlatformException(camera_access_denied) new_event_screen.dart", 0.22),
    ("OutOfMemoryError: image decode (image_vault.dart)", 0.18),
    ("StateError: Bad state: No element (graph_builder.dart)", 0.12),
    ("TimeoutException: Claude API request (anthropic_client.dart)", 0.10),
    ("RangeError: index out of range (force_layout.dart)", 0.08),
)


def _version(moment):
    current = VERSIONS[0][1]
    for since, version in VERSIONS:
        if moment >= since:
            current = version
    return current


def generate(db, end=datetime(2026, 10, 3, 18, 0), days=180, seed=2026,
             installs_per_day=7.0):
    """Fills [db] with about [days] days of activity ending at [end]."""
    rng = random.Random(seed)
    # Stage 2 features draw from their own stream, so adding them left
    # every earlier demo number unchanged.
    stage2 = random.Random(seed + 2)
    store.clear(db)
    start = end - timedelta(days=days)

    installs, accounts, activity, sessions, crashes = [], [], [], [], []
    signatures = [c[0] for c in CRASHES]
    weights = [c[1] for c in CRASHES]

    def act(install, account, moment, kind, value=1):
        activity.append((install, account, store.iso(moment), kind, value))

    n = 0
    for day in range(days):
        # Installs grow slowly, with weekend bumps.
        base = start + timedelta(days=day)
        growth = 0.6 + 0.8 * day / days
        weekend = 1.35 if base.weekday() >= 5 else 1.0
        for _ in range(int(rng.gauss(installs_per_day * growth * weekend, 2)) or 0):
            n += 1
            install = "i%05d" % n
            at = base + timedelta(minutes=rng.randint(0, 1439))
            if at > end:
                continue
            installs.append((install, store.iso(at), "android", _version(at)))
            act(install, None, at, "tutorial_started")
            if rng.random() > 0.84:
                continue
            at += timedelta(minutes=rng.randint(1, 6))
            act(install, None, at, "tutorial_finished")
            if rng.random() > 0.78:
                continue
            act(install, None, at, "signup_started")
            if rng.random() > 0.86:
                continue
            at += timedelta(minutes=rng.randint(1, 4))
            method = rng.choices(store.SIGNUP_METHODS, [46, 18, 30, 6])[0]
            account = "a%05d" % n
            accounts.append((account, install, store.iso(at), method, None))
            act(install, account, at, "signup_completed")

            # How engaged this person is, and for how long they keep going.
            engagement = rng.betavariate(1.3, 3.5)
            lifetime_days = rng.expovariate(1 / (12 + 160 * engagement))
            events = photos = described_photos = videos = rings = 0
            graph = export = False
            moment = at
            session_no = 0
            while True:
                gap_days = rng.expovariate(0.25 + 2.2 * engagement)
                moment += timedelta(days=gap_days, minutes=rng.randint(0, 600))
                if moment > end or (moment - at).days > lifetime_days:
                    break
                session_no += 1
                version = _version(moment)
                minutes = round(max(0.3, rng.lognormvariate(1.2 + engagement, 0.7)), 1)
                crashed = rng.random() < (0.012 if version == "1.0.0" else
                                          0.007 if version == "1.0.1" else 0.004)
                session = "%s-s%d" % (account, session_no)
                sessions.append((session, install, account, store.iso(moment),
                                 minutes, 1 if crashed else 0, version))
                act(install, account, moment, "app_open")
                if crashed:
                    crashes.append((
                        session + "-c", session, account,
                        store.iso(moment + timedelta(minutes=minutes)), version,
                        rng.choices(signatures, weights)[0], ""))
                if rng.random() < 0.55 + 0.4 * engagement:
                    new_events = 1 + int(rng.random() < 0.3)
                    for _ in range(new_events):
                        pics = rng.choice((1, 1, 2, 3, 4, 6))
                        events += 1
                        photos += pics
                        act(install, account, moment, "event_created")
                        act(install, account, moment, "photo_added", pics)
                        if rng.random() < 0.86:
                            described_photos += pics
                            act(install, account, moment, "event_described")
                        if rng.random() < 0.18:
                            act(install, account, moment, "memory_saved")
                        if stage2.random() < 0.3 + 0.4 * engagement:
                            act(install, account, moment, "free_write_saved")
                    if not graph and described_photos >= 10:
                        graph = True
                        act(install, account, moment, "graph_unlocked")
                    if not export and events >= 100:
                        export = True
                        act(install, account, moment, "export_unlocked")
                if rng.random() < 0.06 + 0.1 * engagement:
                    for _ in range(3):
                        videos += 1
                        act(install, account, moment, "ad_watched")
                    act(install, account, moment, "weather_lookup",
                        rng.randint(1, 4))
                if graph and rng.random() < 0.05:
                    for _ in range(5 + rings):
                        videos += 1
                        act(install, account, moment, "ad_watched")
                    rings += 1
                    act(install, account, moment, "ring_unlocked")
                if graph and stage2.random() < 0.25 + 0.5 * engagement:
                    act(install, account, moment, "mind_map_opened")
                    for _ in range(stage2.choice((0, 0, 1, 2, 3))):
                        act(install, account, moment, "mind_map_centered")
                if export and rng.random() < 0.04:
                    act(install, account, moment, "export")
            if rng.random() < 0.025:
                accounts[-1] = accounts[-1][:4] + (
                    store.iso(min(end, moment + timedelta(days=2))),)

    with db:
        db.executemany("INSERT INTO installs VALUES (?, ?, ?, ?)", installs)
        db.executemany("INSERT INTO accounts VALUES (?, ?, ?, ?, ?)", accounts)
        db.executemany(
            "INSERT INTO activity(install_id, account_id, at, kind, value)"
            " VALUES (?, ?, ?, ?, ?)", activity)
        db.executemany("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
                       sessions)
        db.executemany("INSERT INTO crashes VALUES (?, ?, ?, ?, ?, ?, ?)",
                       crashes)
        store.set_meta(db, "source", "demo")
    feature_counts = generate_features(db, end, seed)
    return {**feature_counts,"installs": len(installs), "accounts": len(accounts),
            "activity": len(activity), "sessions": len(sessions),
            "crashes": len(crashes)}


# name, category, status, start offset (days before end), quality 0-1,
# feedback rounds, vote round?, outcome, description
FEATURES = (
    ("Mind-map branch zoom", "experimental", "launched", 150, 0.93, 2, True,
     "dedicated update", "Pinch a branch to open it as its own mind map."),
    ("Voice notes on events", "new", "launched", 140, 0.78, 2, True,
     "next major version", "Record a short voice note instead of typing."),
    ("Graph time-lapse replay", "frontier", "launched", 120, 0.91, 3, True,
     "dedicated update", "Replay how the map grew, month by month."),
    ("Batch describe 20 events", "expert", "held", 110, 0.62, 1, False,
     "pending", "Queue up to 20 events for the AI at once."),
    ("Offline describe queue", "edge case", "failed", 100, 0.35, 1, False,
     "retired", "Hold descriptions while offline and send them later."),
    ("Ring colour gradients", "experimental", "launched", 95, 0.82, 2, True,
     "holiday or promotional event", "Two-colour gradient rings."),
    ("Memory recall quiz", "unique", "launched", 70, 0.80, 3, False,
     "pending", "A weekly quiz built from your own events."),
    ("Shared family Books", "new", "launched", 24, 0.78, 2, False,
     "pending", "Invite family members to add events to one Book."),
    ("Weather radar overlay", "experimental", "launched", 22, 0.92, 1, True,
     "pending", "See the weather radar for the event's hour."),
    ("Keyboard-first graph editing", "expert", "held", 60, 0.70, 1, False,
     "pending", "Arrange Books and rings from a keyboard."),
    ("Raw photo (DNG) import", "edge case", "failed", 80, 0.41, 2, False,
     "back to testing", "Import camera raw files with full detail."),
    ("Time capsule Books", "unique", "scheduled", -12, 0.0, 2, True,
     "pending", "Seal a Book until a future date."),
    ("Chapter titles in 12 languages", "frontier", "scheduled", -20, 0.0, 1,
     True, "pending", "AI chapter titles in the reader's language."),
    ("Holiday memory cards", "new", "scheduled", -45, 0.0, 1, True,
     "pending", "Shareable cards made from a year's events."),
)

COMMENTS = {
    5: ("Love this, I use it every day.", "Exactly what I wanted.",
        "Works perfectly on my phone.", "Please ship this to everyone."),
    4: ("Really good, a little slow on big libraries.",
        "Great idea; the button is hard to find.", "Nearly there."),
    3: ("It's fine but I wouldn't miss it.", "Confusing the first time.",
        "Useful sometimes."),
    2: ("Crashed once while I was using it.", "Too complicated for me.",
        "Not sure what it's for."),
    1: ("Broke my timeline view.", "Didn't work at all.",
        "Please remove this."),
}


def generate_features(db, end, seed):
    """Test features with feedback and vote rounds, reviews and the
    collectables issued for features that passed the 90% vote."""
    rng = random.Random(seed + 1)
    accounts = [dict(r) for r in db.execute(
        "SELECT account_id, created_at, deleted_at FROM accounts")]
    features, rounds, reviews, collectables = [], [], [], []
    ordered = sorted(FEATURES, key=lambda f: -f[3])
    for n, (name, category, status, offset, quality, feedback_rounds, vote,
            outcome, description) in enumerate(ordered, 1):
        feature_id = "FT-%02d" % n
        start = end - timedelta(days=offset)
        created = start - timedelta(days=21)
        planned = feedback_rounds + (1 if vote else 0)
        if status == "scheduled":
            features.append((feature_id, name, category, description, status,
                             store.iso(start), store.iso(created), "1.2.0",
                             planned, outcome, None, 0.9))
            continue
        version = _version(start)
        moment = start
        status_date = start
        outcome_date = None
        total = feedback_rounds + (1 if vote else 0)
        yes_share = None
        for rnd in range(1, total + 1):
            kind = "vote" if vote and rnd == total else "feedback"
            opened = moment
            length = 14 if kind == "feedback" else 10
            closed = opened + timedelta(days=length)
            is_open = closed > end
            if status in ("held", "failed") and rnd == total:
                closed = min(closed, end - timedelta(days=rng.randint(3, 20)))
                is_open = False
            # Testers are people who used the app while the round was open.
            window_end = store.iso(min(closed, end))
            using = {r[0] for r in db.execute(
                "SELECT DISTINCT account_id FROM sessions WHERE started_at >= ?"
                " AND started_at <= ?", (store.iso(opened), window_end))}
            eligible = [a for a in accounts if a["account_id"] in using
                        and not (a["deleted_at"] and a["deleted_at"] <= store.iso(opened))]
            invited = min(len(eligible), rng.randint(140, 260))
            pool = rng.sample(eligible, invited) if invited else []
            rate = 0.35 + 0.35 * rng.random()
            answering = pool[:int(invited * rate)]
            last_day = min(closed, end)
            span = max(1, (last_day - opened).days)
            first_use = dict(db.execute(
                "SELECT account_id, MIN(started_at) FROM sessions WHERE"
                " started_at >= ? AND started_at <= ? GROUP BY account_id",
                (store.iso(opened), window_end)).fetchall())
            for account in answering:
                # Each review is sent during a session in the round.
                at = datetime.fromisoformat(first_use[account["account_id"]]) + \
                    timedelta(minutes=rng.randint(1, 20))
                if at > end:
                    continue
                rid = "%s-R%d-%s" % (feature_id, rnd, account["account_id"])
                if kind == "feedback":
                    centre = 1 + 4 * min(1.0, quality + 0.04 * rnd)
                    rating = max(1, min(5, int(round(rng.gauss(centre, 0.8)))))
                    comment = rng.choice(COMMENTS[rating]) if rng.random() < 0.55 else ""
                    reviews.append((rid, feature_id, rnd, account["account_id"],
                                    store.iso(at), rating, None, comment,
                                    _version(at)))
                else:
                    roll = rng.random()
                    choice = "abstain" if roll < 0.05 else (
                        "yes" if rng.random() < quality else "no")
                    comment = ("Yes, ship it." if choice == "yes" else
                               "Not ready yet." if choice == "no" else "")
                    if rng.random() > 0.3:
                        comment = ""
                    reviews.append((rid, feature_id, rnd, account["account_id"],
                                    store.iso(at), None, choice, comment,
                                    _version(at)))
            if kind == "vote":
                cast = [r[6] for r in reviews if r[1] == feature_id and r[2] == rnd
                        and r[6] in ("yes", "no")]
                yes_share = cast.count("yes") / len(cast) if cast else None
            decision = ""
            if not is_open:
                decision = ("Vote closed" if kind == "vote" else
                            "Continue to round %d" % (rnd + 1) if rnd < total
                            else "Review complete")
            if status == "failed" and rnd == total:
                decision = "Stopped: crash reports" if category == "edge case"                     and name.startswith("Offline") else "Stopped: low ratings"
                status_date = closed
            if status == "held" and rnd == total:
                decision = "Held for rework"
                status_date = closed
            rounds.append((feature_id, rnd, kind, store.iso(opened),
                           None if is_open else store.iso(closed), invited,
                           decision))
            moment = closed + timedelta(days=3)
            if not is_open and kind == "vote" and outcome != "pending":
                outcome_date = closed + timedelta(days=7)
                # The owner's rule: 90% "yes" earns a dedicated update.
                if yes_share is not None and yes_share >= 0.9:
                    outcome = "dedicated update"
                elif outcome == "dedicated update":
                    outcome = "next major version"
                decision = "Vote closed: %d%% yes" % round((yes_share or 0) * 100)
        if outcome in ("retired", "back to testing") and status == "failed":
            outcome_date = status_date + timedelta(days=2)
        if outcome_date and outcome_date > end:
            outcome_date = end
        final_outcome = outcome if outcome_date else "pending"
        features.append((feature_id, name, category, description, status,
                         store.iso(status_date if status != "launched" else start),
                         store.iso(created), version, planned, final_outcome,
                         store.iso(outcome_date) if outcome_date else None, 0.9))
        if final_outcome == "dedicated update":
            for account in accounts:
                if account["created_at"] <= store.iso(outcome_date) and not (
                        account["deleted_at"] and account["deleted_at"] <= store.iso(outcome_date)):
                    collectables.append((feature_id, account["account_id"],
                                         store.iso(outcome_date)))
    with db:
        db.executemany("INSERT INTO features VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?,"
                       " ?, ?, ?)", features)
        db.executemany("INSERT INTO feature_rounds VALUES (?, ?, ?, ?, ?, ?, ?)",
                       rounds)
        db.executemany("INSERT INTO feature_reviews VALUES (?, ?, ?, ?, ?, ?, ?,"
                       " ?, ?)", reviews)
        db.executemany("INSERT INTO collectables VALUES (?, ?, ?)", collectables)
    return {"features": len(features), "feature_reviews": len(reviews),
            "collectables": len(collectables)}
