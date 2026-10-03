# EventLens Owner Dashboard

For the owner (architect and developer) and approved integration partners
only. Hand it over by direct message or email; don't post it publicly.

It runs on your own computer and can only be opened from that computer
(it listens on `127.0.0.1`). It shows how the app is used: how many created
accounts actually use EventLens, how far new installs get (reach vs
utilization), the sign-up funnel, weekly retention, feature use, crashes,
and lifetime totals.

Until the app is connected (the final build stage), the dashboard shows
**demo data**, labelled as such on every screen.

This guide covers setting it up, launching the local hosting, and
starting and ending each hosting. The full program guide comes with the
final stage.

---

## 1. Set up (once)

You need **Python 3.9 or newer**. Nothing else to install: the dashboard
uses only what comes with Python.

- **Windows**: install Python from python.org. On the first installer
  screen, tick **Add python.exe to PATH**.
- **macOS**: install Python from python.org (or `brew install python`).
- **Linux**: Python 3 is usually already there (`python3 --version`).

Then unzip the dashboard folder somewhere you'll find it (for example
`Documents/eventlens-dashboard`), open a terminal in that folder, and run:

| Windows (Command Prompt or PowerShell) | macOS / Linux (Terminal) |
|---|---|
| `py -m eventlens_dashboard setup --demo` | `python3 -m eventlens_dashboard setup --demo` |

This creates the dashboard's data folder in your home folder
(`.eventlens-dashboard`) with:

- `metrics.db`: the metrics database (SQLite)
- `config.json`: two private tokens, one the app will use to send
  metrics and one that ends the hosting. Keep this file private.
- `dashboard.log`: the log of background hostings

Leave out `--demo` to start with an empty database. Running `setup` again
is safe: it keeps your tokens.

## 2. Launch the local hosting

The quickest way is to double-click the launcher in the folder:

| | Start | End |
|---|---|---|
| Windows | `start-dashboard.bat` | `stop-dashboard.bat` |
| macOS | `start-dashboard.command` | `stop-dashboard.command` |
| Linux | `start-dashboard.sh` | `stop-dashboard.sh` |

The launchers start the dashboard in the background and open your browser
at **http://127.0.0.1:8787/**. On macOS, the first time, right-click the
`.command` file, choose **Open**, then **Open** again (macOS asks once for
files downloaded from the internet).

## 3. Start and end each hosting from a terminal

There are two ways to host.

**In a window (simplest):** the hosting lasts while the window is open.

```
python3 -m eventlens_dashboard start        # Windows: py -m eventlens_dashboard start
```

The browser opens by itself. To end the hosting, press **Ctrl+C** in that
window (or close the window).

**In the background:** keeps running after you close the terminal.

```
python3 -m eventlens_dashboard start --background
python3 -m eventlens_dashboard status       # is it running, and where?
python3 -m eventlens_dashboard stop         # end the hosting
```

Useful options:

- `--port 8800`: use another port if 8787 is busy (the dashboard tells you
  when it is).
- `--no-browser`: don't open the browser.
- `--data-dir PATH` (before the command): keep the data somewhere else, for
  example an encrypted drive. You can also set the
  `EVENTLENS_DASHBOARD_HOME` variable.

## 4. Using the dashboard

- **Time window**: 7 days, 30 days, 90 days or all time, top right.
- **Meters**: hide any panel with **Hide**, and bring it back from
  **Meters**. Your choice is kept in your browser.
- Every chart has its numbers in a table too (**Show as a table**), and
  hovering the chart shows the values for that day.
- Coloured dots mark state: green **Healthy**, amber **Watch**, red **Needs
  attention**. Thresholds: utilization 40% / 20%, stickiness 20% / 10%,
  crash-free sessions 99.5% / 99%.

What the main measures mean:

| Measure | Meaning |
|---|---|
| Utilization rate | Share of live (not deleted) accounts that opened the app in the window |
| Stickiness | Today's active accounts ÷ active accounts in the last 30 days |
| Reach vs utilization | Installs first seen in the window, and how many reached each milestone: tutorial, account, first event, first AI account, timeline graph (10 photos), 100 events (full export) |
| Sign-up funnel | Tutorial opened → finished → sign-up started → completed, plus the sign-up method mix (email, phone, Google, Web3) |
| Weekly retention | Accounts by sign-up week; share that came back each later week |
| Utilization depth | Live accounts by number of events recorded, all time |
| Crash-free sessions | Sessions without a crash, by app version, plus the most frequent crashes |

## 5. Other commands

```
python3 -m eventlens_dashboard demo                 # replace the data with fresh demo data
python3 -m eventlens_dashboard reset --yes          # delete every stored metric
python3 -m eventlens_dashboard export-demo FILE.html  # one self-contained demo page to share
```

## 6. Security notes

- Only this computer can open the dashboard. Integration partners get
  their own copy or an export, never a link to yours.
- Metrics arrive at `POST /api/ingest` with the ingest token from
  `config.json` (`Authorization: Bearer …`). Batches are all-or-nothing:
  one bad record rejects the batch.
- How the app's metrics reach this computer is decided in the final
  stage (options in `docs/LAUNCH_CHECKLIST.md`). Before any real usage
  data is sent, the privacy policy needs a line about it and the app
  needs to ask for consent.

## 7. For developers

```
cd owner-dashboard
python3 -m unittest discover -s tests -v
```

Layout: `eventlens_dashboard/store.py` (database and every measure),
`server.py` (local web server), `demo.py` (example data),
`__main__.py` (commands), `web/index.html` (the page).
