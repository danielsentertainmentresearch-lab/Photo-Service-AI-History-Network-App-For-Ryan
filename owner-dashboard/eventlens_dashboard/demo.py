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
    return {"installs": len(installs), "accounts": len(accounts),
            "activity": len(activity), "sessions": len(sessions),
            "crashes": len(crashes)}
