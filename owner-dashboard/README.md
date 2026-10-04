# EventLens Owner Dashboard

For the owner (architect and developer) and approved integration partners
only. Hand it over by direct message or email; don't post it publicly.

It runs on your own computer and can only be opened from that computer
(it listens on `127.0.0.1`). It shows how the app is used: how many created
accounts actually use EventLens, how far new installs get (reach vs
utilization), the sign-up funnel, weekly retention, feature use, crashes,
lifetime totals, and the **feature-test archive** (every test feature, its
review stages, the complete review catalog, exports and a built-in Jupyter
notebook).

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

## 5. The feature-test archive

Open **Feature tests** at the top. The archive lists every test feature:

| Column | Meaning |
|---|---|
| # | Row number |
| Archive status | **Launched** (live with testers), **Scheduled** (starts in a coming update), **Held** (paused for rework) or **Failed** (stopped by crashes or low ratings) |
| Status date | The date that goes with the status: launched on, scheduled for, held since, or failed on |
| Feature ID, Feature, Category | Which test, and its kind: edge case, frontier, expert, experimental, unique or new |
| Review stage | Not started, feedback round open, voting open, under review, on hold, stopped or decided |
| Rounds | Finished rounds of planned rounds |
| Reviewers, Reviews, Avg rating | Totals across feedback rounds (ratings 1-5) |
| Yes vote | Latest vote; ✓ means it reached the 90% bar for a dedicated update |
| Outcome | Dedicated update, next major version, holiday or promotional event, back to testing, retired, or pending |
| Collectables | Recognition issued to fully set-up accounts after a dedicated update (never bought or sold) |
| Last activity | The latest date anything happened |

Click a status card to filter, click a column title to sort, and use the
search, category and outcome filters. **Export the archive** gives a simple
list (one row per feature) or the complete list (every review of every
feature), as CSV or JSON.

Open a row to see that feature's page:

- **Review stages**: each feedback and vote round in aggregate, with the
  rating mix and vote shares.
- **Exports**:
  - **simple vector list**: one row per round, as CSV or JSON;
  - **complete vector list**: every review with every field, as CSV or JSON;
  - **custom analysis export**: pick columns, and the catalog filters apply.
    **Open in notebook** opens it in a fresh Jupyter notebook right on the
    page, with no other program, browser tab or window. **Analysis kit
    (.zip)** is for other tools and holds CSV, JSON, a notebook (.ipynb), a
    pandas script (.py), a SQLite database and a README.
  - Every export, and the data the notebook opens, is analysis-ready: no
    cell is blank. The original columns keep their place; after them,
    unknown numbers are -999 with a `_known` 0/1 column, missing categories
    and text are `none`, each category has one 0/1 column per value, and
    date-times have `_weekday` (1 = Monday) and `_hour` columns.
- **Complete review catalog** (optional, opens on request): every review.
  The filters only offer what the selected round contains (ratings in
  feedback rounds, votes in vote rounds, and the versions, sign-up methods,
  account ages and dates that actually occur). It loads more as you scroll.

### Built-in notebook (one-time setup)

The notebook is JupyterLite, the official Jupyter that runs inside the page.
Install it once, with an internet connection:

```
python3 -m eventlens_dashboard notebook-setup     # Windows: py -m eventlens_dashboard notebook-setup
```

It goes into the data folder (about 70 MB). Each **Open in notebook** starts
a new notebook that keeps nothing; use **File → Download** inside it to keep
your work. The first run of each session loads Python (Pyodide) from the
jsDelivr CDN, so it needs internet.

### Find on this screen

Long screens (more than about 30 lines) show a **Find on this screen** line
under the header. Type to highlight matches; Enter or ↓ goes to the next,
Shift+Enter or ↑ to the previous, Esc clears. Ctrl+F (Cmd+F on a Mac) jumps
to it. To search every review, not just the ones on screen, use the
catalog's own search box.

## 6. Other commands

```
python3 -m eventlens_dashboard demo                 # replace the data with fresh demo data
python3 -m eventlens_dashboard reset --yes          # delete every stored metric
python3 -m eventlens_dashboard export-demo FILE.html  # one self-contained demo page to share
```

## 7. Security notes

- Only this computer can open the dashboard. Integration partners get
  their own copy or an export, never a link to yours.
- Metrics arrive at `POST /api/ingest` with the ingest token from
  `config.json` (`Authorization: Bearer …`), as `{"records": [...]}`.
  Record types: `install`, `account`, `account_deleted`, `activity`,
  `session`, `crash`, and for the archive `feature`, `feature_round`,
  `feature_review` and `collectable`. Batches are all-or-nothing: one bad
  record rejects the batch.
- How the app's metrics reach this computer is decided in the final
  stage (options in `docs/LAUNCH_CHECKLIST.md`). Before any real usage
  data is sent, the privacy policy needs a line about it and the app
  needs to ask for consent.

## 8. For developers

```
cd owner-dashboard
python3 -m unittest discover -s tests -v
```

Layout: `eventlens_dashboard/store.py` (database and every measure),
`features.py` (feature-test archive, filters and exports),
`server.py` (local web server), `demo.py` (example data),
`__main__.py` (commands), `web/index.html` (the page).
