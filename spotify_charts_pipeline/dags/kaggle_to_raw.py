"""Kaggle -> raw Postgres: downloads the Spotify charts files and loads them into raw-db.

    download_files -> load_<table> (x4) -> check_raw_quality -> trigger_dbt_transform

  * download_files      downloads the four CSV files from Kaggle with kagglehub. Files are cached
                        in /opt/airflow/data/kaggle, so a re-run does not download them again.
  * load_<table>        loads one CSV into the raw Postgres database (raw-db, schema raw).
                        DuckDB reads the CSV and writes into Postgres through its postgres
                        extension, which is much faster than row-by-row inserts.
                          - songs, artists: full snapshot -> delete all rows, insert all rows
                          - chart tables:   only rows from start_date on -> delete that window,
                                            insert that window
                        Both run in one transaction, so a run never leaves a half-loaded table,
                        and running the DAG again for the same input gives the same result.
  * check_raw_quality   data-quality checks on the raw tables; fails the run if the load looks
                        wrong (empty window, NULL keys, duplicate chart positions, bad ranks).
  * trigger_dbt_transform starts the dbt_transform DAG with the same start_date, once the raw
                        data has passed the checks.

Parameters (Trigger DAG w/ config): start_date (first chart date to load) and
dataset_version (Kaggle dataset version; empty = latest).
"""

import os
import shutil
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.models.param import Param
from airflow.operators.python import PythonOperator
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

CONN_ID = "raw_db"
KAGGLE_HANDLE = "gonzalopezgil/spotify-charts-daily-updated"

# Raw tables: column order = CSV header = raw table definition (sql/create_raw_tables.sql).
# is_chart = True -> only rows from start_date on are loaded (column "date").
TABLES = {
    "songs": {
        "is_chart": False,
        "columns": ["track_uri", "track_name", "artist_names", "artist_uris", "label",
                    "release_date", "all_uris"],
    },
    "artists": {
        "is_chart": False,
        "columns": ["artist_uri", "artist_name", "monthly_listeners", "monthly_listeners_rank",
                    "monthly_listeners_peak_rank", "monthly_listeners_peak_listeners"],
    },
    "charts_songs_daily": {
        "is_chart": True,
        "columns": ["date", "country", "rank", "uri", "artist_names", "track_name", "label",
                    "peak_rank", "previous_rank", "days_on_chart", "streams", "consecutive_days",
                    "entry_status", "peak_date", "entry_rank", "entry_date", "release_date",
                    "artist_uris"],
    },
    "charts_artists_daily": {
        "is_chart": True,
        "columns": ["date", "country", "rank", "uri", "artist_name", "peak_rank",
                    "previous_rank", "days_on_chart", "consecutive_days", "entry_status",
                    "peak_date", "entry_rank", "entry_date"],
    },
}

default_args = {
    "owner": "airflow",
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}


def _duckdb_with_raw_db():
    """In-memory DuckDB connection with the raw Postgres database attached as 'pg'."""
    import duckdb

    con = duckdb.connect()
    con.sql(f"SET memory_limit = '{os.environ.get('DUCKDB_MEMORY_LIMIT', '4GB')}'")
    con.sql("SET preserve_insertion_order = false")
    con.sql("LOAD postgres")
    con.sql(
        "ATTACH '"
        f"host={os.environ['RAW_DB_HOST']} port=5432 dbname={os.environ['RAW_DB_NAME']} "
        f"user={os.environ['RAW_DB_USER']} password={os.environ['RAW_DB_PASSWORD']}"
        "' AS pg (TYPE postgres)"
    )
    return con


def download_files(**context):
    """Step 1 -- download the four CSV files from Kaggle. Only this task needs the internet.

    Kaggle credentials are optional: the dataset is public, so without credentials kagglehub
    tries an anonymous download. With credentials (KAGGLE_USERNAME / KAGGLE_KEY in .env) it
    downloads as that Kaggle user.
    """
    if os.environ.get("KAGGLE_USERNAME") and os.environ.get("KAGGLE_KEY"):
        print("Kaggle credentials found: downloading as a logged-in user.")
    else:
        # compose.yml passes these as empty strings when .env does not set them. Remove them,
        # so kagglehub does not try to log in with empty credentials.
        os.environ.pop("KAGGLE_USERNAME", None)
        os.environ.pop("KAGGLE_KEY", None)
        print("WARNING: no Kaggle credentials in .env, trying an anonymous download. "
              "If this fails with 401/403, add KAGGLE_USERNAME and KAGGLE_KEY to .env (see README).")

    # imported after the credential check, so kagglehub sees the cleaned-up environment
    import time

    import kagglehub
    import kagglehub.clients
    import requests

    # kagglehub gives up when the server sends nothing for 15 s, which happens now and then during
    # the 10 GB charts_songs_daily download. Allow longer pauses (read at call time, so this works).
    kagglehub.clients.DEFAULT_READ_TIMEOUT = 120

    version = str(context["params"]["dataset_version"] or "").strip()
    if version.lower() == "latest":
        version = ""  # same as empty; kagglehub only accepts a version number
    handle = f"{KAGGLE_HANDLE}/versions/{version}" if version else KAGGLE_HANDLE

    def download_with_resume(file_name, attempts=10):
        # A dropped connection leaves the partial file on disk, and kagglehub continues it with an
        # HTTP Range request on the next call. So retrying here resumes the download; it does not
        # start the 10 GB file again. A file only counts as cached once it is complete.
        for attempt in range(1, attempts + 1):
            try:
                return kagglehub.dataset_download(handle, path=file_name)
            except (requests.exceptions.ConnectionError,
                    requests.exceptions.ChunkedEncodingError,
                    requests.exceptions.Timeout) as e:
                if attempt == attempts:
                    raise
                wait = min(10 * attempt, 60)
                print(f"{file_name}: download interrupted ({e.__class__.__name__}), "
                      f"resuming in {wait} s (attempt {attempt + 1}/{attempts})")
                time.sleep(wait)

    paths = {}
    for table in TABLES:
        # One file at a time: the full-dataset archive can be unavailable right after a daily update.
        paths[table] = download_with_resume(f"{table}.csv")
        print(f"{table}: {paths[table]} ({os.path.getsize(paths[table]) / 1e9:.2f} GB)")
        if not version:
            # Pin the version after the first file (path ends in .../versions/<n>/<file>), so all
            # four files come from the same version even if Kaggle publishes a new one mid-run.
            version = os.path.basename(os.path.dirname(paths[table]))
            handle = f"{KAGGLE_HANDLE}/versions/{version}"

    # Kaggle publishes a new dataset version every day, and kagglehub keeps each version in its own
    # folder (.../versions/<n>/). Delete the older versions, so the cache stays at one copy (~14 GB)
    # instead of growing by ~14 GB per day.
    current_version_dir = os.path.dirname(paths["songs"])
    versions_dir = os.path.dirname(current_version_dir)
    for name in os.listdir(versions_dir):
        old_dir = os.path.join(versions_dir, name)
        if old_dir != current_version_dir and os.path.isdir(old_dir):
            shutil.rmtree(old_dir)
            print(f"Deleted old dataset version: {old_dir}")

    # Only file paths go through XCom, never the data itself
    return paths


def load_table(table, **context):
    """Step 2 -- load one CSV into raw.<table> in Postgres. Idempotent (delete + insert)."""
    start_date = context["params"]["start_date"]
    csv_path = context["ti"].xcom_pull(task_ids="download_files")[table]
    spec = TABLES[table]

    cols = ", ".join(f'"{c}"' for c in spec["columns"])
    # all_varchar: every column is read as text, like the raw table; staging does the casts
    source = f"read_csv('{csv_path}', header = true, all_varchar = true)"
    if spec["is_chart"]:
        # Dates are ISO strings, so a text comparison works (and can use the index on "date")
        window = f"WHERE \"date\" >= '{start_date}'"
    else:
        window = ""

    con = _duckdb_with_raw_db()
    con.begin()
    con.sql(f"DELETE FROM pg.raw.{table} {window}")
    con.sql(f"INSERT INTO pg.raw.{table} ({cols}) SELECT {cols} FROM {source} {window}")
    con.commit()

    rows = con.sql(f"SELECT COUNT(*) FROM pg.raw.{table} {window}").fetchone()[0]
    con.close()
    print(f"raw.{table}: {rows:,} rows loaded" + (f" from {start_date}" if window else ""))
    if rows == 0:
        raise ValueError(f"raw.{table} is empty after the load")


def check_raw_quality(**context):
    """Step 3 -- data-quality checks on the raw layer. Fails the run if any check fails,
    so dbt is never triggered on a bad load."""
    start_date = context["params"]["start_date"]
    pg = PostgresHook(postgres_conn_id=CONN_ID)

    # (description, query returning one number that must be 0)
    checks = []
    for table in ["charts_songs_daily", "charts_artists_daily"]:
        checks += [
            (f"{table}: no rows from {start_date}",
             f"SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM raw.{table} WHERE \"date\" >= %(d)s"),
            (f"{table}: rows with NULL date, country, rank or uri",
             f"SELECT COUNT(*) FROM raw.{table} WHERE \"date\" >= %(d)s "
             f"AND (\"date\" IS NULL OR country IS NULL OR \"rank\" IS NULL OR uri IS NULL)"),
            (f"{table}: duplicate chart positions (date, country, rank)",
             f"SELECT COUNT(*) FROM (SELECT 1 FROM raw.{table} WHERE \"date\" >= %(d)s "
             f"GROUP BY \"date\", country, \"rank\" HAVING COUNT(*) > 1) x"),
            (f"{table}: rank outside 1-200",
             f"SELECT COUNT(*) FROM raw.{table} WHERE \"date\" >= %(d)s "
             f"AND CAST(\"rank\" AS INTEGER) NOT BETWEEN 1 AND 200"),
        ]
    checks += [
        ("songs: duplicate track_uri",
         "SELECT COUNT(*) - COUNT(DISTINCT track_uri) FROM raw.songs"),
        ("artists: duplicate artist_uri",
         "SELECT COUNT(*) - COUNT(DISTINCT artist_uri) FROM raw.artists"),
    ]

    failed = []
    for name, sql in checks:
        value = pg.get_first(sql, parameters={"d": start_date})[0]
        print(f"{'OK  ' if value == 0 else 'FAIL'} {name}: {value}")
        if value != 0:
            failed.append(f"{name}: {value}")
    if failed:
        raise ValueError("Data-quality checks failed:\n" + "\n".join(failed))



with DAG(
    dag_id="kaggle_to_raw",
    description="Download the Spotify charts from Kaggle and load them into the raw Postgres database",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    # No schedule: the DAG runs when it is triggered (▶ in the UI, or `airflow dags trigger`).
    # Kaggle publishes a new version daily, so every manual run gets the latest data.
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    params={
        "start_date": Param(os.environ.get("PIPELINE_START_DATE", "2025-01-01"), type="string",
                            format="date", description="First chart date to load"),
        "dataset_version": Param(os.environ.get("KAGGLE_DATASET_VERSION", ""), type="string",
                                 description="Kaggle dataset version number, e.g. 159; "
                                             "empty or 'latest' = newest version"),
    },
    tags=["spotify", "ingestion", "postgres"],
) as dag:

    t_download = PythonOperator(
        task_id="download_files",
        python_callable=download_files,
        # Only this task talks to the network, so it gets extra retries
        retries=3,
    )

    t_loads = [
        PythonOperator(
            task_id=f"load_{table}",
            python_callable=load_table,
            op_kwargs={"table": table},
        )
        for table in TABLES
    ]

    t_quality = PythonOperator(
        task_id="check_raw_quality",
        python_callable=check_raw_quality,
    )

    # Hand over to the dbt DAG, with the same analysis window. The dbt DAG can also be run on its own.
    t_trigger_dbt = TriggerDagRunOperator(
        task_id="trigger_dbt_transform",
        trigger_dag_id="dbt_transform",
        conf={"start_date": "{{ params.start_date }}"},
        wait_for_completion=False,
    )

    # Loads one after another (chain), so only one task writes to the raw database at a time
    t_download >> t_loads[0]
    for upstream, downstream in zip(t_loads, t_loads[1:]):
        upstream >> downstream
    t_loads[-1] >> t_quality >> t_trigger_dbt
