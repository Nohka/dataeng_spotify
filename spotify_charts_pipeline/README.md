# Spotify Charts Pipeline

Data pipeline for the Kaggle dataset [Spotify Charts (Daily Updated)](https://www.kaggle.com/datasets/gonzalopezgil/spotify-charts-daily-updated).
Airflow downloads the data and loads it into a raw Postgres database; dbt builds a star schema in a
DuckDB warehouse that answers five business questions. Both layers are browsed with DBeaver.

The setup follows the course's `03_Airflow` example (separate Postgres for Airflow metadata and pipeline
data, `airflow-init` / `-webserver` / `-scheduler` with LocalExecutor, `.env.example` with defaults) and
the course's `06_dbt` example (dbt project in its own folder, profile inside the project, a Dockerfile
for dbt).

## Business questions

1. For a given artist, in which country is their chart presence the strongest?
2. What is the hottest song in Estonia this week?
3. Which record labels are consistently producing hits?
4. Which songs are breaking out (largest week-over-week stream growth among songs not in the Top 20 the week before)?
5. How long does a song typically stay on the chart after release, and does it differ by country?

## Architecture

```
 Kaggle (4 CSV files, ~14 GB)
      │
      │  DAG kaggle_to_raw: download_files → load_<table> ×4 → check_raw_quality → trigger_dbt_transform
      ▼
 ┌──────────────────────────────┐
 │ raw-db (Postgres)            │   bronze: the CSV files as text columns
 │ schema raw: 4 tables         │
 └──────────────┬───────────────┘
                │  attached read-only as catalog "raw"
                │  DAG dbt_transform: dbt_build
                ▼
 ┌──────────────────────────────────────────────┐
 │ warehouse: data/warehouse/spotify.duckdb     │
 │   stg_*           renames, types, window     │   silver (views)
 │   int_*           all logic                  │
 │   mart_* / dim_*  star schema                │   gold (tables)
 └──────────────────────────────────────────────┘

 airflow-db (Postgres): Airflow's own metadata
```


**Star schema (gold layer).** The gold models are tables stored in the DuckDB file; the silver models
(`stg_*`, `int_*`) are views (see *Why views for silver and tables for gold*).

| Model | Type | Grain | Questions |
|---|---|---|---|
| `mart_artist_country_weekly_presence` | Fact | week × country × artist | Q1 |
| `mart_songs_weekly` | Fact | week × country × song | Q2, Q3, Q4 |
| `mart_song_chart_lifespan` | Fact | song × country | Q5 |
| `dim_song` | Dimension (SCD 1) | song | — |
| `dim_artist` | Dimension (SCD 1) | artist | — |

## Repository structure

```
spotify_charts_pipeline/
├── compose.yml                 # all services
├── Dockerfile                  # Airflow image + dbt (own venv) + duckdb + kagglehub
├── .env.example                # settings with defaults; copy to .env to change them
├── dags/
│   ├── kaggle_to_raw.py        # DAG 1: Kaggle -> raw Postgres, quality checks
│   └── dbt_transform.py        # DAG 2: dbt build (stg -> int -> mart) in DuckDB
├── sql/
│   ├── create_raw_tables.sql   # raw schema, applied when raw-db is first created
│   └── queries/                # the five business-question queries
├── dbt_project/
│   ├── dbt_project.yml
│   ├── profiles.yml            # DuckDB warehouse + raw Postgres attached as "raw"
│   ├── models/{staging,intermediate,marts}/
│   └── tests/                  # custom data tests
├── notebooks/
│   └── data_pipelines.ipynb    # data discovery and the prototype of the models
├── data/                       # created at run time: Kaggle files, warehouse, dbt artifacts (gitignored)
└── logs/                       # Airflow and dbt logs (gitignored)
```

## Requirements

- Docker Desktop with at least **8 GB of memory** (Settings → Resources)
- About **30 GB of free disk**: ~14 GB for the Kaggle files, the rest for Postgres
- [DBeaver](https://dbeaver.io/download/) (free Community edition) to browse the data. On an Apple
  Silicon Mac (M1–M4) install the **Apple Silicon** version: the download page's big button may offer
  the Intel one, and its DuckDB driver fails (see Troubleshooting)
- No Kaggle account needed: the dataset is public and is downloaded anonymously

## Local services and credentials

| What | Address | User | Password |
|---|---|---|---|
| Airflow UI | http://localhost:8080 | `airflow` | `airflow` |
| Raw database (Postgres) | `localhost:5433`, database `spotify_raw` | `raw_user` | `raw_pass` |
| Warehouse (DuckDB file) | `data/warehouse/spotify.duckdb` in the project folder | | |

These are local defaults from `.env.example`. To change them, copy it to `.env` and edit
(`cp .env.example .env`), then run `docker compose up -d`.

## Step 1: start the stack

Get the whole project folder (clone the repository, or copy the complete `spotify_charts_pipeline`
folder, including `dbt_project/` with all its subfolders). Run all commands from that folder.

```bash
docker compose up -d --build
docker compose ps -a
```

The first build takes a few minutes (it installs dbt and DuckDB's postgres extension). Wait until
`airflow-init` shows **Exited (0)**, `airflow-db` and `raw-db` show **healthy**, and
`airflow-webserver` and `airflow-scheduler` show **Up**. `airflow-init` only runs once to set up
Airflow (database, admin user, `raw_db` connection) and then exits. Re-running `docker compose up -d`
is safe.

Open Airflow at http://localhost:8080 (`airflow` / `airflow`). You should see two DAGs,
**kaggle_to_raw** and **dbt_transform**, both paused, and no red "DAG Import Errors" banner.

## Step 2: load the Kaggle data into the raw tables

The DAG **kaggle_to_raw** does the ingestion:

<img width="1077" height="103" alt="image" src="https://github.com/user-attachments/assets/800b8328-b37b-4b7d-bd82-c3796d75afb1" />

_Figure 1. Airflow DAG graph for kaggle_to_raw._


| Task | What it does | Result |
|---|---|---|
| `download_files` | Downloads the 4 CSV files from Kaggle with kagglehub | Files in `data/kaggle/` (cached for later runs) |
| `load_songs`, `load_artists` | Full snapshot: deletes all rows and inserts the file, in one transaction | Rows in `raw.songs`, `raw.artists` |
| `load_charts_songs_daily`, `load_charts_artists_daily` | Deletes rows from `start_date` on and inserts the file's rows from `start_date` on, in one transaction | Rows in `raw.charts_*` |
| `check_raw_quality` | Fails the run if the window is empty, keys are NULL, a chart position appears twice, a rank is outside 1–200, or a song/artist URI is duplicated | Pass or fail |
| `trigger_dbt_transform` | Starts the DAG **dbt_transform** with the same `start_date` | — |



The 4 raw tables already exist (created empty when raw-db first starts); they get rows in the load tasks.

**2a. Download the files first (recommended the first time).** The download is ~14 GB, about
20 minutes. Running it on its own gets the long wait out of the way:

```bash
docker compose exec airflow-scheduler airflow tasks test kaggle_to_raw download_files 2026-10-29
```

This runs only `download_files`, in your terminal, while the DAG is still paused. It does not appear in
the Airflow UI and does not load anything into the database. Keep the terminal open until it lists all
four files and prints `Marking task as SUCCESS`.

**2b. Run the DAG.** In the Airflow UI, switch on the toggle next to **kaggle_to_raw** (a paused DAG
does not run, even when triggered), then press **▶ Trigger DAG**. The DAG has no schedule: it runs only
when it is triggered. `download_files` finds the files from 2a and finishes in seconds; the four load
tasks take a few minutes each.



Follow the run: click **kaggle_to_raw** → **Grid**. Green = success; for a red task, click it → **Logs**.

Leave **dbt_transform** paused for now. Its run, started by `trigger_dbt_transform`, waits as *queued*
until step 4.

**Parameters.** The run uses `start_date` 2025-01-01 (chart rows from that date on) and the latest
dataset version. To change them for one run, use *Trigger DAG w/ config* (`start_date`,
`dataset_version`); to change the defaults, set `PIPELINE_START_DATE` / `KAGGLE_DATASET_VERSION` in `.env`.

**Only data from `start_date` on is loaded.** Kaggle offers each chart table as one CSV file with
all years (2017 onwards), so the download always includes older data. The load tasks skip it: only
rows from `start_date` on reach Postgres, and dbt only reads those.

**Idempotency.** Every load deletes exactly what it inserts, inside one transaction, so running the DAG
again for the same input gives the same tables and never creates duplicates.

## Step 3: browse the raw tables in DBeaver

Connections and schemas are listed in DBeaver's **Database Navigator** (if it is not shown:
**Window** → **Database Navigator**).

New connection → **PostgreSQL** (DBeaver fills in port 5432; change it to **5433**):

| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `5433` |
| Database | `spotify_raw` |
| Username | `raw_user` |
| Password | `raw_pass` |

The tables are under **spotify_raw** → **Schemas** → **raw** → **Tables**. Open a table and use the
*Data* tab, or open an SQL editor and check the row counts:

```sql
SELECT 'songs' AS t, COUNT(*) FROM raw.songs
UNION ALL SELECT 'artists', COUNT(*) FROM raw.artists
UNION ALL SELECT 'charts_songs_daily', COUNT(*) FROM raw.charts_songs_daily
UNION ALL SELECT 'charts_artists_daily', COUNT(*) FROM raw.charts_artists_daily;
```

Expect roughly 215k songs, 74k artists and about 9 million rows in each chart table with `start_date`
2025-01-01 (more as the dataset grows). If the tables are empty, the load tasks have not finished yet:
refresh (F5) once they are green. If the `raw` schema is missing, right-click **Schemas** → **Refresh**.

Example query:

```sql
SELECT "date", country, "rank", track_name, streams
FROM raw.charts_songs_daily
WHERE country = 'ee'
ORDER BY "date" DESC, "rank"::int
LIMIT 20;
```

`date` and `rank` need double quotes because they are also SQL keywords. All raw columns are text (the
dbt staging models do the type casts), so `"rank"::int` makes the sort numeric.

## Step 4: build the dbt models

In the Airflow UI, switch on the toggle next to **dbt_transform**. The queued run from step 2 starts and
runs `dbt build`: it creates the silver models (stg, int) as views and the gold models (mart, dim) as
tables in the DuckDB warehouse, and
runs every dbt test, in dependency order. dbt reads the raw tables straight from Postgres.

<img width="202" height="98" alt="image" src="https://github.com/user-attachments/assets/26678b8b-af70-4e08-b9cb-c8f7d27bd62d" />

_Figure 2. Airflow DAG graph for dbt_transform._

<img width="1164" height="848" alt="image" src="https://github.com/user-attachments/assets/c310b450-4fa8-4489-8134-d8d0110ac6b1" />

_Figure 3. dbt model dependencies._


From then on, every successful **kaggle_to_raw** run triggers **dbt_transform**, as long as both DAGs
are switched on. You can also trigger **dbt_transform** on its own (▶ in the UI), e.g. after changing a
model.

## Step 5: browse the dbt models in DBeaver

The warehouse file `data/warehouse/spotify.duckdb` exists after the first successful **dbt_transform** run.

1. New connection → **DuckDB**. Path: `data/warehouse/spotify.duckdb` in the project folder (use
   *Browse*). Let DBeaver download the driver when it asks.
2. Open the file read-only: the pipeline writes to it, and DuckDB allows only one writer at a time.
   - **Driver properties** tab: right-click **User Properties** → *Add new property*, name
     `duckdb.read_only`, value `true`.
   - Click **Finish**. Then right-click the connection → **Edit Connection** → **Connection settings**
     → **General**: tick **Read-only connection**.
3. In the same dialog, **Connection settings → Initialization → Bootstrap queries → Configure…**: add
   these three queries (one per *Add*). DBeaver runs them every time it connects:

   ```sql
   INSTALL postgres;
   LOAD postgres;
   ATTACH 'host=localhost port=5433 dbname=spotify_raw user=raw_user password=raw_pass' AS raw (TYPE postgres, READ_ONLY);
   ```

   The `stg_*` and `int_*` views read the raw tables through a catalog called `raw`; without this
   attachment, querying them fails with `Catalog "raw" does not exist`. The alias must be exactly `raw`.
   (The `mart_*` and `dim_*` tables are stored in the file and work without it.)
   `INSTALL postgres` downloads DuckDB's postgres extension the first time (needs internet).
   Type the quotes as straight `'`, not curly `‘ ’`: macOS may replace them automatically (see
   Troubleshooting).
4. Connect (or disconnect and connect again: bootstrap queries only run when the connection opens).
   Check that both catalogs are there with `SELECT database_name FROM duckdb_databases();`: it should
   list `spotify` and `raw`. Under **spotify** → **main**, the `mart_*` and `dim_*` models are in
   **Tables** and the `stg_*` and `int_*` models in **Views**; the raw tables are under **raw** → **raw**.
   In SQL, use the model name directly (`dim_song`) or the full name `spotify.main.dim_song`. Open a
   model and use the *Data* tab, or run SQL:

   ```sql
   SELECT *
   FROM mart_songs_weekly
   WHERE country_code = 'ee'
   ORDER BY week_start DESC, streams_rank_in_week
   LIMIT 20;
   ```

The `mart_*` and `dim_*` tables answer queries almost instantly. The `stg_*` and `int_*` views compute
their results from the raw tables on every query, so querying them can take a few seconds.

**Disconnect the DuckDB connection before dbt_transform runs** (right-click → *Disconnect*): while DBeaver
has the file open, dbt cannot rebuild the models and the task fails with a lock error.

**Business questions.** The five queries are in `sql/queries/`. Open a file in DBeaver's SQL editor on the
DuckDB connection and run it. Q1 is written for one artist (`'Taylor Swift'`); change the name in
`q1_artist_strongest_country.sql`.

### Results for the example analytical SQL queries

1. For a given artist, in which country is their chart presence the strongest?
<img width="943" height="136" alt="image" src="https://github.com/user-attachments/assets/69e6bcc4-9b2e-4b3b-b824-89f70d493dc8" />

2. What is the hottest song in Estonia this week?
<img width="1037" height="129" alt="image" src="https://github.com/user-attachments/assets/0b46ae40-859f-41fd-9059-41b9eff30071" />

3. Which record labels are consistently producing hits?
<img width="885" height="231" alt="image" src="https://github.com/user-attachments/assets/0009d453-a339-4ae4-b2aa-a6c9de136f54" />

4. Which songs are breaking out (largest week-over-week stream growth among songs not in the Top 20 the week before)?
<img width="1078" height="129" alt="image" src="https://github.com/user-attachments/assets/5bd07815-124b-4e16-b0a9-131a51c76230" />

5. How long does a song typically stay on the chart after release, and does it differ by country? (Example for Estonia, Finland and USA)
<img width="1020" height="88" alt="image" src="https://github.com/user-attachments/assets/464daf05-6145-4571-98e0-7a297a28e56f" />


## Getting the latest data later

The pipeline runs on demand, not on a schedule. To refresh the data:

1. Disconnect DBeaver's DuckDB connection (while it is connected, `dbt_build` cannot write the warehouse
   file; the task retries 3 times, 10 minutes apart, before it fails).
2. In the Airflow UI, press **▶ Trigger DAG** on **kaggle_to_raw** (both DAGs must be switched on). It
   downloads the newest dataset version, reloads the raw tables from `start_date` on and triggers
   **dbt_transform**, which rebuilds the gold tables.
3. Keep the computer awake until both runs are green: the download is ~14 GB (~20 minutes), and if the
   computer sleeps, it fails with `Read timed out`.
4. Reconnect DBeaver to see the new data.

Kaggle publishes a new version every day, so a run on a later day downloads the ~14 GB again.
`download_files` deletes the previous version afterwards, so the cache stays at one copy.

To change `start_date`, set `PIPELINE_START_DATE` in `.env`, run `docker compose up -d`, then trigger
**kaggle_to_raw**; the load and dbt run use the new window.

## Useful commands

```bash
docker compose ps -a                                     # status of all services
docker compose logs -f airflow-scheduler                 # task output, DAG import errors
docker compose exec airflow-scheduler airflow dags trigger kaggle_to_raw    # refresh the data (also ▶ in the UI)
docker compose stop                                      # pause everything, keep all data
docker compose start                                     # continue
docker compose down                                      # remove containers (data stays in pgdata_*/ and data/)
docker compose down && rm -rf pgdata_airflow pgdata_raw  # reset both databases
```

dbt by hand, inside the scheduler container:

```bash
docker compose exec airflow-scheduler bash
cd /opt/airflow/dbt_project
$DBT_BIN build                                   # all models + tests
$DBT_BIN build --select int_songs_weekly+        # one model and everything downstream
$DBT_BIN build --vars '{"start_date": "2025-01-01"}'
$DBT_BIN docs generate                           # lineage graph in data/dbt/target
```

## Why views for silver and tables for gold

| | Silver: `stg_*`, `int_*` — **views** | Gold: `mart_*`, `dim_*` — **tables** |
|---|---|---|
| What is stored | Only the SQL | The calculated rows, in the DuckDB file |
| When it is calculated | On every query | Once per `dbt build` |
| Reads Postgres | Yes, on every query | Only while dbt builds it |
| Why | Always reflects the latest load; no storage; no incremental logic (e.g. when a song's main URI changes, `song_id` is recalculated for the whole history) | Reporting queries are fast and work without the raw database; the star schema exists as physical tables |

The gold tables are fully rebuilt on every run, never updated incrementally, for the same reason: a
changed song URI must be re-mapped for the whole history.

## Why Postgres for raw data and DuckDB for the warehouse

| | Raw layer: **Postgres** | Warehouse: **DuckDB** |
|---|---|---|
| Workload | Bulk loads (delete + insert of a date window), quality checks | Scans and aggregations over millions of chart rows (weekly roll-ups, window functions, medians) |
| Storage | Row-oriented server with users and transactions | Columnar and vectorised: reads only the columns a query needs, uses all CPU cores |
| Why here | A proper database server for the bronze layer that other tools can connect to; mirrors the course setup | The models were developed on DuckDB; aggregations over ~4M rows per chart table run in seconds without indexes or tuning |
| Limits | Slower for analytical queries on large tables | A file, not a server: one writer at a time, so tasks run one after another and DBeaver opens it read-only |

The gold tables use DuckDB's columnar storage: a query that needs a few columns of `mart_songs_weekly`
reads only those columns from the file, compressed.

DuckDB reads the raw tables straight from Postgres through its `postgres` extension
(`ATTACH ... (TYPE postgres)`), so no copy step is needed between the layers. The DuckDB-specific SQL in
the models (`QUALIFY`, `ARG_MIN`/`ARG_MAX`, `GROUP BY ALL`, `MEDIAN`, `UNNEST(STRING_SPLIT(...))`) would
need rewriting to run on Postgres.

## Data quality

- **In the DAG** (`check_raw_quality`): row counts, NULL keys, duplicate chart positions, rank range,
  duplicate URIs in the dimension files.
- **In dbt** (`dbt build`): `unique` / `not_null` on every key, uniqueness of every model's grain,
  `relationships` from each fact to its dimension, and custom tests in `dbt_project/tests/`
  (duplicate rows must have equal streams; warning if many chart URIs are missing from `songs.csv`).

Main findings from data discovery (details in `notebooks/data_pipelines.ipynb` and the model comments):

- One song can have several Spotify URIs (single, album version, re-release). `songs.all_uris` maps
  them to one `song_id`; their streams are summed at song level.
- The same URI can appear twice on one chart day with identical streams: one entry recorded twice,
  kept once at the better rank.
- In the artist chart, a second artist with the same name is sometimes listed under another artist's
  URI ("side history", e.g. two artists named Luis Gabriel in Romania). Side histories are removed;
  moving them to the right URI was tested and is not reliable.
- `release_date` is the date of the album a track is currently linked to, often later than the first
  release. Q5 uses the earlier of `release_date` and the first chart entry.
- `entry_date`, `peak_rank` and `days_on_chart` are counted from the start of the dataset (left-censored).

## Troubleshooting

- **`download_files` fails with 401/403**: Kaggle refused the anonymous download. Add your own Kaggle
  API token (Kaggle → Settings → API → *Create New Token*) as `KAGGLE_USERNAME` / `KAGGLE_KEY` in `.env`,
  then run `docker compose up -d`.
- **`download_files` fails with 404**: Kaggle has not finished building the newest dataset version.
  Trigger with `dataset_version` set to the previous version number (see the dataset page).
- **`download_files` fails with `Read timed out`**: the connection to Kaggle's file storage dropped
  during the download, usually because the computer went to sleep. Delete the partial download (the
  newest, much smaller folder under `data/kaggle/.../versions/`), keep the computer awake and trigger
  **kaggle_to_raw** again.
- **Runs download ~14 GB again**: the cached files belong to one dataset version (shown in the path,
  e.g. `data/kaggle/.../versions/149`), and Kaggle publishes a new version daily. While testing, set
  `KAGGLE_DATASET_VERSION=149` in `.env` (then `docker compose up -d`) to keep using the files you have.
- **`dbt_build` fails with a lock error**: DBeaver still has the DuckDB file open. Disconnect it and
  re-run the task (click it → *Clear*).
- **`dbt_build` fails with `No dbt_project.yml found`**: the `dbt_project/` folder is empty or
  incomplete (Docker creates an empty folder if it is missing). Copy the complete folder into the project
  so that `dbt_project/dbt_project.yml` exists, then *Clear* the task. No restart is needed.
- **DBeaver: `DuckDB JNI library not found ... macos_amd64`**: the Intel version of DBeaver is running on
  an Apple Silicon Mac (Activity Monitor shows *Kind = Intel*). Install the Apple Silicon version, then
  **Database** → **Driver Manager** → **DuckDB** → **Edit** → **Libraries**: delete the entry and
  *Download/Update*.
- **DBeaver: `Connection to localhost:5432 refused`**: the PostgreSQL connection uses DBeaver's default
  port. Change it to **5433** (right-click the connection → *Edit Connection*).
- **DBeaver: `Catalog "raw" does not exist` or `schema "raw.raw" does not exist`**: the `ATTACH`
  bootstrap query did not run. Check that its quotes are straight `'`, not curly `‘ ’` (macOS replaces
  them automatically: System Settings → Keyboard → Text Input → Edit → turn off *Use smart quotes and
  dashes*), then disconnect and connect. Running the `ATTACH` line in the SQL editor shows its error.
- **A task is killed or DuckDB reports out of memory**: give Docker more memory, or lower
  `DUCKDB_MEMORY_LIMIT` in `.env`.
- **`container raw-db is unhealthy`**: usually a corrupt data directory:
  `docker compose down && rm -rf pgdata_airflow pgdata_raw && docker compose up -d`.
- **Changed `sql/create_raw_tables.sql`**: it only runs when raw-db is created; remove `pgdata_raw`
  and start again.
- **Platform mismatch errors** (Apple Silicon): `unset DOCKER_DEFAULT_PLATFORM`.
