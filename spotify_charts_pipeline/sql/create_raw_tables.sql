-- Raw (bronze) layer: the Kaggle CSV files as they are.
-- Applied automatically the first time raw-db is created (mounted into /docker-entrypoint-initdb.d).
-- To re-run it, remove ./pgdata_raw and bring the stack back up.
--
-- All columns are TEXT on purpose: the raw layer stores the files unchanged, and the dbt staging
-- models own the type casts. Column order matches the CSV headers.
-- _loaded_at records when the Airflow DAG loaded each row.

CREATE SCHEMA IF NOT EXISTS raw;

-- Full snapshot, replaced on every DAG run
CREATE TABLE IF NOT EXISTS raw.songs (
    track_uri           TEXT,
    track_name          TEXT,
    artist_names        TEXT,
    artist_uris         TEXT,
    label               TEXT,
    release_date        TEXT,
    all_uris            TEXT,
    _loaded_at          TIMESTAMPTZ DEFAULT now()
);

-- Full snapshot, replaced on every DAG run
CREATE TABLE IF NOT EXISTS raw.artists (
    artist_uri                          TEXT,
    artist_name                         TEXT,
    monthly_listeners                   TEXT,
    monthly_listeners_rank              TEXT,
    monthly_listeners_peak_rank         TEXT,
    monthly_listeners_peak_listeners    TEXT,
    _loaded_at                          TIMESTAMPTZ DEFAULT now()
);

-- Daily chart, loaded from the DAG's start_date onwards (delete + insert for that window)
CREATE TABLE IF NOT EXISTS raw.charts_songs_daily (
    "date"              TEXT,
    country             TEXT,
    "rank"              TEXT,
    uri                 TEXT,
    artist_names        TEXT,
    track_name          TEXT,
    label               TEXT,
    peak_rank           TEXT,
    previous_rank       TEXT,
    days_on_chart       TEXT,
    streams             TEXT,
    consecutive_days    TEXT,
    entry_status        TEXT,
    peak_date           TEXT,
    entry_rank          TEXT,
    entry_date          TEXT,
    release_date        TEXT,
    artist_uris         TEXT,
    _loaded_at          TIMESTAMPTZ DEFAULT now()
);

-- Daily chart, loaded from the DAG's start_date onwards (delete + insert for that window)
CREATE TABLE IF NOT EXISTS raw.charts_artists_daily (
    "date"              TEXT,
    country             TEXT,
    "rank"              TEXT,
    uri                 TEXT,
    artist_name         TEXT,
    peak_rank           TEXT,
    previous_rank       TEXT,
    days_on_chart       TEXT,
    consecutive_days    TEXT,
    entry_status        TEXT,
    peak_date           TEXT,
    entry_rank          TEXT,
    entry_date          TEXT,
    _loaded_at          TIMESTAMPTZ DEFAULT now()
);

-- Dates are ISO strings (YYYY-MM-DD), so text comparison sorts correctly and these indexes
-- speed up the DAG's "DELETE ... WHERE date >= start_date".
CREATE INDEX IF NOT EXISTS ix_charts_songs_daily_date   ON raw.charts_songs_daily ("date");
CREATE INDEX IF NOT EXISTS ix_charts_artists_daily_date ON raw.charts_artists_daily ("date");
