"""EventLens owner dashboard: command line.

    python -m eventlens_dashboard setup [--demo]
    python -m eventlens_dashboard start [--background] [--port 8787]
    python -m eventlens_dashboard status
    python -m eventlens_dashboard stop
    python -m eventlens_dashboard demo
    python -m eventlens_dashboard notebook-setup
    python -m eventlens_dashboard export-demo FILE.html
    python -m eventlens_dashboard reset --yes

Everything lives in one data folder (default: ~/.eventlens-dashboard, or
--data-dir / the EVENTLENS_DASHBOARD_HOME variable).
"""

import argparse
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

from . import demo, features, server, store

DEFAULT_PORT = 8787


def data_dir(args):
    folder = Path(args.data_dir or os.environ.get("EVENTLENS_DASHBOARD_HOME")
                  or Path.home() / ".eventlens-dashboard")
    return folder.expanduser().resolve()


def paths(folder):
    return {
        "db": folder / "metrics.db",
        "config": folder / "config.json",
        "pid": folder / "dashboard.pid",
        "log": folder / "dashboard.log",
        "notebook_env": folder / "notebook-env",
        "notebook_build": folder / "notebook-build",
        "notebook_site": folder / "notebook-site",
    }

# The JupyterLite versions this dashboard was tested with.
NOTEBOOK_PACKAGES = ("jupyterlite-core==0.8.5",
                     "jupyterlite-pyodide-kernel==0.8.6")


def load_config(folder):
    path = paths(folder)["config"]
    if not path.exists():
        raise SystemExit(
            "Not set up yet. Run:  python -m eventlens_dashboard setup --demo")
    return json.loads(path.read_text(encoding="utf-8"))


def cmd_setup(args):
    folder = data_dir(args)
    folder.mkdir(parents=True, exist_ok=True)
    p = paths(folder)
    if p["config"].exists():
        config = json.loads(p["config"].read_text(encoding="utf-8"))
        print("Already set up in %s (keeping your tokens)." % folder)
    else:
        config = {
            "port": args.port or DEFAULT_PORT,
            "ingest_token": secrets.token_urlsafe(24),
            "admin_token": secrets.token_urlsafe(24),
        }
        p["config"].write_text(json.dumps(config, indent=2), encoding="utf-8")
        try:
            os.chmod(p["config"], 0o600)
        except OSError:
            pass
        print("Set up in %s" % folder)
    db = store.connect(str(p["db"]))
    if args.demo:
        counts = demo.generate(db)
        print("Loaded demo data: %(accounts)d accounts, %(sessions)d sessions."
              % counts)
    db.close()
    print("Next:  python -m eventlens_dashboard start")
    return 0


def _running(folder):
    """(pid, port) of a hosting that answers, else None."""
    p = paths(folder)
    if not p["pid"].exists():
        return None
    try:
        info = json.loads(p["pid"].read_text(encoding="utf-8"))
        with urllib.request.urlopen(
                "http://127.0.0.1:%d/api/health" % info["port"], timeout=2):
            return info["pid"], info["port"]
    except (OSError, ValueError, KeyError, urllib.error.URLError):
        return None


def cmd_start(args):
    folder = data_dir(args)
    config = load_config(folder)
    p = paths(folder)
    port = args.port or config.get("port", DEFAULT_PORT)
    running = _running(folder)
    if running:
        print("Already running at http://127.0.0.1:%d/" % running[1])
        return 0

    if args.background:
        command = [sys.executable, "-m", "eventlens_dashboard", "start",
                   "--port", str(port), "--data-dir", str(folder), "--no-browser"]
        log = open(p["log"], "a", encoding="utf-8")
        options = {"stdout": log, "stderr": log, "stdin": subprocess.DEVNULL,
                   "cwd": str(Path(__file__).resolve().parent.parent)}
        if os.name == "nt":
            options["creationflags"] = (subprocess.DETACHED_PROCESS |
                                        subprocess.CREATE_NEW_PROCESS_GROUP)
        else:
            options["start_new_session"] = True
        subprocess.Popen(command, **options)
        for _ in range(50):
            time.sleep(0.2)
            if _running(folder):
                url = "http://127.0.0.1:%d/" % port
                print("Started in the background at %s" % url)
                print("End it with:  python -m eventlens_dashboard stop")
                if not args.no_browser:
                    webbrowser.open(url)
                return 0
        print("It didn't start. See %s" % p["log"])
        return 1

    try:
        httpd = server.DashboardServer(str(p["db"]), config, port,
                                       notebook_dir=str(p["notebook_site"]))
    except OSError as error:
        print("Port %d is busy (%s). Try:  start --port %d"
              % (port, error.strerror, port + 1))
        return 1
    server.write_pid(p["pid"], port)
    print("EventLens dashboard running at %s" % httpd.url)
    print("Only this computer can open it. Press Ctrl+C to end this hosting.")
    sys.stdout.flush()
    if not args.no_browser:
        webbrowser.open(httpd.url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        try:
            p["pid"].unlink()
        except OSError:
            pass
        print("Hosting ended.")
    return 0


def cmd_stop(args):
    folder = data_dir(args)
    config = load_config(folder)
    running = _running(folder)
    if not running:
        print("Not running.")
        try:
            paths(folder)["pid"].unlink()
        except OSError:
            pass
        return 0
    request = urllib.request.Request(
        "http://127.0.0.1:%d/api/shutdown" % running[1], data=b"{}",
        headers={"Authorization": "Bearer " + config["admin_token"],
                 "Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(request, timeout=5).read()
    for _ in range(50):
        time.sleep(0.1)
        if not _running(folder):
            print("Hosting ended.")
            return 0
    print("It didn't stop in time; close the window it runs in.")
    return 1


def cmd_status(args):
    folder = data_dir(args)
    running = _running(folder)
    if running:
        print("Running at http://127.0.0.1:%d/ (process %d)"
              % (running[1], running[0]))
    else:
        print("Not running.")
    return 0


def cmd_notebook_setup(args):
    """Installs the built-in notebook (JupyterLite) into the data folder.
    Needs an internet connection once; the dashboard serves it from then on."""
    folder = data_dir(args)
    load_config(folder)
    p = paths(folder)
    env = p["notebook_env"]
    print("Setting up the built-in notebook in %s (one time, needs internet)." % folder)
    if not env.exists():
        try:
            subprocess.run([sys.executable, "-m", "venv", str(env)], check=True)
        except subprocess.CalledProcessError:
            print("Couldn't create a Python environment. On Debian or Ubuntu run:"
                  "  sudo apt install python3-venv  and try again.")
            return 1
    bin_dir = env / ("Scripts" if os.name == "nt" else "bin")
    python = bin_dir / ("python.exe" if os.name == "nt" else "python")
    try:
        subprocess.run([str(python), "-m", "pip", "install", "--quiet",
                        "--disable-pip-version-check"] + list(NOTEBOOK_PACKAGES),
                       check=True)
        build = p["notebook_build"]
        build.mkdir(exist_ok=True)
        (build / "jupyter-lite.json").write_text(json.dumps({
            "jupyter-lite-schema-version": 0,
            "jupyter-config-data": {
                "appName": "EventLens notebook",
                # Nothing is kept between openings: each notebook starts new.
                "enableMemoryStorage": True,
                # The dashboard serves each fresh notebook and its data file
                # at api/contents/all.json and files/.
                "contentsAllJsonFile": "all.json",
            },
        }, indent=2), encoding="utf-8")
        subprocess.run([str(python), "-m", "jupyterlite_core", "build",
                        "--output-dir", str(p["notebook_site"])],
                       cwd=str(build), check=True)
    except subprocess.CalledProcessError:
        print("Setup didn't finish. Check the internet connection and run it again.")
        return 1
    print("Done. Start the dashboard and use 'Open in notebook' on any test feature.")
    return 0


def cmd_demo(args):
    folder = data_dir(args)
    load_config(folder)
    db = store.connect(str(paths(folder)["db"]))
    counts = demo.generate(db)
    db.close()
    print("Loaded demo data: %(accounts)d accounts, %(sessions)d sessions."
          % counts)
    return 0


def build_demo_page(db=None):
    """A single self-contained page with demo metrics for every window."""
    own = db is None
    db = db or store.connect(":memory:")
    if own:
        demo.generate(db)
    data = {window: store.metrics(db, window) for window in store.WINDOWS}
    rows = features.archive(db)
    data["features"] = {
        "rows": rows,
        "summary": features.summary(db),
        "statuses": features.STATUS_LABELS,
        "status_date_labels": features.STATUS_DATE_LABELS,
        "notebook": {"installed": False},
        "details": {r["feature_id"]: features.detail(db, r["feature_id"])
                    for r in rows},
    }
    if own:
        db.close()
    return server.full_page(data)


def cmd_export_demo(args):
    Path(args.file).write_text(build_demo_page(), encoding="utf-8")
    print("Wrote %s" % args.file)
    return 0


def cmd_reset(args):
    if not args.yes:
        print("This deletes every stored metric. Run again with --yes.")
        return 1
    folder = data_dir(args)
    load_config(folder)
    db = store.connect(str(paths(folder)["db"]))
    store.clear(db)
    db.close()
    print("All metrics deleted.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m eventlens_dashboard",
                                     description="EventLens owner dashboard")
    parser.add_argument("--data-dir", help="where metrics and settings live")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("setup", help="create the data folder and tokens")
    p.add_argument("--demo", action="store_true", help="load demo data")
    p.add_argument("--port", type=int)
    p.set_defaults(run=cmd_setup)

    p = sub.add_parser("start", help="start hosting the dashboard")
    p.add_argument("--background", action="store_true",
                   help="keep running after this window closes")
    p.add_argument("--port", type=int)
    p.add_argument("--no-browser", action="store_true")
    p.add_argument("--data-dir", default=argparse.SUPPRESS,
                   help=argparse.SUPPRESS)
    p.set_defaults(run=cmd_start)

    for name, run, text in (("stop", cmd_stop, "end a background hosting"),
                            ("status", cmd_status, "is it running?"),
                            ("demo", cmd_demo, "replace data with demo data")):
        p = sub.add_parser(name, help=text)
        p.add_argument("--data-dir", default=argparse.SUPPRESS,
                   help=argparse.SUPPRESS)
        p.set_defaults(run=run)

    p = sub.add_parser("notebook-setup",
                       help="install the built-in Jupyter notebook (once)")
    p.add_argument("--data-dir", default=argparse.SUPPRESS,
                   help=argparse.SUPPRESS)
    p.set_defaults(run=cmd_notebook_setup)

    p = sub.add_parser("export-demo", help="write a self-contained demo page")
    p.add_argument("file")
    p.set_defaults(run=cmd_export_demo)

    p = sub.add_parser("reset", help="delete all metrics")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--data-dir", default=argparse.SUPPRESS,
                   help=argparse.SUPPRESS)
    p.set_defaults(run=cmd_reset)

    args = parser.parse_args(argv)
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
