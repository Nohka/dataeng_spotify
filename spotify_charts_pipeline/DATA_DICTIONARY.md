# Data Dictionary — Spotify Charts Warehouse


Column types are the types DuckDB reports. Sums of integers are reported as `HUGEINT`; read them as integers.

## Conventions

| Topic | Rule |
|---|---|
| Layers | **Bronze** `raw.*` (Postgres) → **silver** `stg_*`, `int_*` (dbt views) → **gold** `mart_*`, `dim_*` (dbt tables). |
| Keys | Natural keys: `song_id` (the song's main URI), `artist_uri`, `label_key` (`LOWER(TRIM(label))`). `dim_date` uses the calendar day itself, `date_key` (DATE). No surrogate keys. |
| Week identity | Weekly facts carry `week_start`, the **Monday** of the ISO week. It joins to `dim_date.date_key`; every `week_start` has a matching `dim_date` row. |
| Songs and URIs | One song can have several Spotify URIs (single, album version, re-release). `songs.all_uris` lists them all; every chart row gets a `song_id`. |
| Unknown members | `dim_song.is_unknown_song` and `dim_artist.is_unknown_artist` mark members found on the charts but missing from `songs.csv` / `artists.csv`, so no fact row loses its dimension member. A song without a label has `label_key = NULL` (there is no "unknown label" member); the relationships test ignores NULLs. |
| Country | `country_code` is a lower-case ISO-2 code, or `'global'` for the worldwide chart. `'global'` overlaps the real countries: exclude it when adding up across countries (`mart_artist_country_weekly_presence` already excludes it). |
| Additivity | `weekly_streams`, `stream_gain_wow`, `days_on_chart`, `chart_days`, `rank_sum`, `presence_points` are additive. `best_rank` and `avg_rank` are **semi-additive**: never SUM them. `stream_growth_pct_wow` is a **ratio**: never SUM it. |
| Complete weeks | A country-week is complete when the chart has all 7 days (`is_complete_week`). The first and the latest week are usually incomplete; filter on it before comparing weeks. |

---

# 1. Bronze layer — `raw` schema (PostgreSQL)

Kaggle *Spotify Charts Daily Updated*, loaded by the Airflow DAG. Every column is `TEXT` and the files are stored as they are; the dbt staging models own the casts. Each table also has `_loaded_at` (timestamp of the load). Defined in `sql/create_raw_tables.sql`.

| Table | Grain | Load | Notes |
|---|---|---|---|
| `raw.charts_songs_daily` | date × country × rank | rows from `start_date` on; delete + insert in one transaction | Daily Top-200 song chart with streams. |
| `raw.charts_artists_daily` | date × country × rank | rows from `start_date` on; delete + insert in one transaction | Daily artist chart. No streams. |
| `raw.songs` | `track_uri` | full snapshot, replaced on every run | Song metadata. `all_uris` lists every URI of the song. |
| `raw.artists` | `artist_uri` | full snapshot, replaced on every run | Artist metadata. Listener columns are not used downstream. |

The source offers each chart table as one CSV with all years (2017 on); the load tasks skip rows before `start_date`, so only the window reaches Postgres.

### Known source characteristics

Figures were measured during data discovery (`notebooks/data_pipelines.ipynb`) and can differ for other start dates or dataset versions.

| Characteristic | Measured | Handling |
|---|---|---|
| Same song URI twice on one chart day (different ranks) | 192 cases, always with identical streams | One entry recorded twice: `int_charts_songs_daily` keeps the better rank. Test `assert_duplicate_song_rows_have_equal_streams` guards the assumption. |
| One song under several URIs | `songs.all_uris` | Mapped to one `song_id` in `int_song_uri_map`; streams of different URIs are summed at song level. These are *not* duplicates. |
| Chart URIs missing from `songs.csv` | 43 URIs (no name or label) | Keep their own URI as `song_id` and are added to `dim_song` as unknown songs. Warning test `assert_chart_uris_are_mapped` fires above 100. |
| Same-name artist listed under another artist's URI | e.g. two Luis Gabriel (ro), VCT (vn) | "Side histories" (later chart histories of the same URI and country) are removed in `int_charts_artists_daily`. |
| Artist names are not unique | 329 names map to more than one artist | Always key on `artist_uri`. |
| Missing label | many chart rows | `label = NULL` (empty strings become NULL in staging); excluded from the label question Q3. |
| `release_date` is the album the track is linked to **now** | often later than the first release | `mart_song_chart_lifespan` uses the earlier of `release_date` and the first chart entry anywhere. |
| `entry_date`, `peak_rank`, `days_on_chart` | counted from the start of the dataset | Left-censored: they go back before `start_date`. |

---

# 2. Silver layer — staging (`stg_*`, views)

Renames and casts only; `-1 → NULL` on `previous_rank`, `'' → NULL` on labels. The only filter is the analysis window (`chart_date >= start_date`) on the two chart files. No joins, no derived columns.

### `stg_charts_songs_daily`
Grain: `chart_date` × `country_code` × `chart_rank`.

| Column | Type | Description |
|---|---|---|
| `chart_date` | DATE | Chart day. Not null. |
| `country_code` | VARCHAR | Lower-case ISO-2 market, or `'global'`. Not null. |
| `chart_rank` | INTEGER | Position on the chart, 1–200. Not null. |
| `track_uri` | VARCHAR | Spotify track URI **as published** (release-specific); resolved to a song in `int_charts_songs_daily`. Not null. |
| `track_name` | VARCHAR | Song title on the chart row. |
| `artist_names` | VARCHAR | `|`-separated artist names. |
| `artist_uris` | VARCHAR | `|`-separated artist URIs. |
| `label` | VARCHAR | Record label, trimmed; NULL when empty. |
| `streams` | BIGINT | Streams that day in that country. |
| `peak_rank` | INTEGER | Best position reached to date. |
| `previous_rank` | INTEGER | Position the previous day; source `-1` becomes NULL. |
| `days_on_chart`, `consecutive_days` | INTEGER | The source's own running counts. |
| `entry_status` | VARCHAR | Entry status as published. |
| `peak_date`, `entry_date` | DATE | Date the peak was reached; date of first entry on this country's chart (counted from the start of the dataset). |
| `entry_rank` | INTEGER | Position on first entry. |
| `release_date` | DATE | Release date of the album the track is currently linked to. Often later than the real first release. |

### `stg_charts_artists_daily`
Grain: `chart_date` × `country_code` × `chart_rank`. Same chart columns as above (`chart_date`, `country_code`, `chart_rank`, `peak_rank`, `previous_rank`, `days_on_chart`, `consecutive_days`, `entry_status`, `peak_date`, `entry_rank`, `entry_date`; no streams, track or label columns) plus:

| Column | Type | Description |
|---|---|---|
| `artist_uri` | VARCHAR | Spotify artist URI. Not null. |
| `artist_name` | VARCHAR | Artist name on the chart row. |

`entry_date` is not null here: together with `artist_uri` and `country_code` it identifies one *chart history*.

### `stg_songs`
Grain: `track_uri` (unique, not null).

| Column | Type | Description |
|---|---|---|
| `track_uri` | VARCHAR | The song's main URI, used as `song_id` downstream. |
| `track_name` | VARCHAR | Song title. |
| `artist_names`, `artist_uris` | VARCHAR | `|`-separated, aligned. |
| `label` | VARCHAR | Record label, trimmed; NULL when empty. |
| `release_date` | DATE | Release date (TRY_CAST; NULL if invalid). |
| `all_uris` | VARCHAR | `|`-separated list of every URI of this song. |

### `stg_artists`
Grain: `artist_uri` (unique, not null).

| Column | Type | Description |
|---|---|---|
| `artist_uri` | VARCHAR | Spotify artist URI. |
| `artist_name` | VARCHAR | Display name. **Not unique.** `'N/A'` and `'None'` are real values in the source, not NULLs. |
| `monthly_listeners`, `monthly_listeners_peak_listeners` | BIGINT | Listener snapshot; not used downstream. |
| `monthly_listeners_rank`, `monthly_listeners_peak_rank` | INTEGER | Listener rank snapshot; not used downstream. |

---

# 3. Silver layer — intermediate (`int_*`, views)

All joins, key resolution and metrics live here; the gold models only expose them.

| Model | Grain | Purpose |
|---|---|---|
| `int_song_uri_map` | `track_uri` | Maps every URI in `songs.all_uris` to its song. |
| `int_charts_songs_daily` | `chart_date` × `country_code` × `track_uri` | Cleaned daily song chart with `song_id` and `week_start`. |
| `int_charts_artists_daily` | `chart_date` × `country_code` × `artist_uri` | Daily artist chart without side histories. |
| `int_song` | `song_id` | Logic of `dim_song`. |
| `int_artist` | `artist_uri` | Logic of `dim_artist`. |
| `int_label` | `label_key` | Logic of `dim_label`. |
| `int_date` | calendar day | Logic of `dim_date`. |
| `int_songs_weekly` | `week_start` × `country_code` × `song_id` | Logic of `mart_songs_weekly`. |
| `int_artist_country_weekly_presence` | `week_start` × `country_code` × `artist_uri` | Logic of `mart_artist_country_weekly_presence`. |
| `int_song_chart_lifespan` | `song_id` × `country_code` | Logic of `mart_song_chart_lifespan`. |

The three `int_` models behind a fact or dimension have the same columns as the gold model and are documented in section 4. The others:

### `int_song_uri_map`
| Column | Type | Description |
|---|---|---|
| `track_uri` | VARCHAR | Any Spotify URI of a song. **Unique**, not null; the test fails the build if a URI is ever listed under two songs. |
| `song_id` | VARCHAR | The song's main URI (`songs.track_uri`). Not null. |

Must stay a view (or a fully rebuilt table): if the source changes a song's main URI, all chart rows have to be re-mapped.

### `int_charts_songs_daily`
Grain: `chart_date` × `country_code` × `track_uri`; also unique on (`chart_date`, `country_code`, `chart_rank`).

A URI that appears twice on one day (identical streams) is kept once, at the better rank. Different URIs of the same song on the same day are **kept as separate rows**: they have their own streams and chart history, and are combined later in `int_songs_weekly`.

| Column | Type | Description |
|---|---|---|
| `chart_date` | DATE | Chart day. |
| `week_start` | DATE | Monday of the chart day's ISO week. |
| `country_code` | VARCHAR | Market or `'global'`. |
| `chart_rank` | INTEGER | Position, 1–200. |
| `track_uri` | VARCHAR | URI as published. |
| `song_id` | VARCHAR | Song the URI belongs to (`int_song_uri_map`); falls back to `track_uri` for URIs missing from `songs.csv`. Not null. |
| `track_name`, `artist_names`, `label` | VARCHAR | As on the chart row. |
| `streams` | BIGINT | Streams that day. |
| `entry_date` | DATE | First entry date on this country's chart (left-censored). |
| `release_date` | DATE | Release date as published on the chart row. |

### `int_charts_artists_daily`
Grain: `chart_date` × `country_code` × `artist_uri`; also unique on (`chart_date`, `country_code`, `chart_rank`). Columns as in `stg_charts_artists_daily`.

The oldest chart history of an artist URI in a country owns the URI; later histories of the same URI and country that collide with it on the same day (side histories) are deleted. Moving them to the right URI was tested and is not reliable. Duplicate rows for the same URI and day are reduced to the best rank.

---

# 4. Gold layer — star schema (`mart_*`, `dim_*`, tables in DuckDB)

```
                  dim_date
                 /        \
   mart_songs_weekly    mart_artist_country_weekly_presence
        /      \                        |
   dim_song dim_label               dim_artist
      |
mart_song_chart_lifespan
```

Three facts and four dimensions. `mart_songs_weekly` and `mart_artist_country_weekly_presence` are **periodic snapshot** facts (one row per week); `mart_song_chart_lifespan` is an **accumulating** fact (one row per song and country, updated as the run grows).

| Fact | Joins to |
|---|---|
| `mart_songs_weekly` | `dim_date` (`week_start = date_key`), `dim_song` (`song_id`), `dim_label` (`label_key`) |
| `mart_artist_country_weekly_presence` | `dim_date` (`week_start = date_key`), `dim_artist` (`artist_uri`) |
| `mart_song_chart_lifespan` | `dim_song` (`song_id`) |

## `mart_songs_weekly`
**Grain: one row per ISO week × country × song that charted.** Questions: Q2 (hottest song), Q3 (labels with hits), Q4 (breakouts).

Different URIs of one song are combined: streams are summed, rank is the best position of any URI.

| Column | Type | Key / measure | Description |
|---|---|---|---|
| `week_start` | DATE | FK → `dim_date.date_key` | Monday of the ISO week. |
| `country_code` | VARCHAR | Degenerate dim | Market or `'global'`. |
| `song_id` | VARCHAR | FK → `dim_song.song_id` | Song (main URI). |
| `track_name` | VARCHAR | Attribute | Name from the song's best-ranked row of the week. |
| `artist_names` | VARCHAR | Attribute | `|`-separated names, from the best-ranked row of the week. |
| `label` | VARCHAR | Attribute | Label from the best-ranked row of the week that has one; NULL if none. |
| `label_key` | VARCHAR | FK → `dim_label.label_key` | `LOWER(TRIM(label))`; NULL if the song has no label. |
| `weekly_streams` | HUGEINT | Additive | Sum of daily streams over all days and all URIs of the song. Only streams while in the Top 200 are known. |
| `best_rank` | INTEGER | Semi-additive | Best daily rank of any URI that week (lowest number). Never SUM. |
| `days_on_chart` | BIGINT | Additive | Distinct chart days (a day with two URIs counts once), 1–7. |
| `is_complete_week` | BOOLEAN | Flag | The country's chart has all 7 days in this week. |
| `is_prev_week_complete` | BOOLEAN | Flag | The country's previous week exists, is exactly 7 days earlier and has all 7 days. Needed so a short previous week does not inflate growth. |
| `prev_week_streams` | HUGEINT | Additive | `weekly_streams` of the song's previous week; NULL unless that week is exactly 7 days earlier (NULL after a gap). |
| `prev_week_best_rank` | INTEGER | Semi-additive | `best_rank` of the previous week; NULL after a gap. |
| `stream_gain_wow` | HUGEINT | Additive | `weekly_streams − prev_week_streams`; a new entry gains all its streams. **Q4's ranking measure.** |
| `stream_growth_pct_wow` | DOUBLE | Ratio | Week-over-week growth in %, rounded to 1 decimal. NULL if the song was not on the chart last week. Never SUM. |
| `was_outside_top_n_prev_week` | BOOLEAN | Flag | The song's best rank last week was worse than 20 (the `breakout_top_n` parameter in the model), or it did not chart. Not charting counts as outside. |
| `streams_rank_in_week` | BIGINT | Rank | Position of the song in this country and week by streams (1 = most streamed; ties broken by `best_rank`). **Q2's measure.** |

## `mart_artist_country_weekly_presence`
**Grain: one row per ISO week × country × artist that charted.** Question: Q1 (strongest country). `'global'` is excluded.

All metrics are additive or rebuildable from additive ones, so any period can be computed by summing weeks.

| Column | Type | Key / measure | Description |
|---|---|---|---|
| `week_start` | DATE | FK → `dim_date.date_key` | Monday of the ISO week. |
| `country_code` | VARCHAR | Degenerate dim | Market (never `'global'`). |
| `artist_uri` | VARCHAR | FK → `dim_artist.artist_uri` | Artist. |
| `artist_name` | VARCHAR | Attribute | From `artists.csv` when present, otherwise the latest chart spelling. **Not unique.** |
| `chart_days` | BIGINT | Additive | Days the artist was on the country's chart that week, 1–7. |
| `best_rank` | INTEGER | Semi-additive | Best daily rank that week. Never SUM. |
| `rank_sum` | HUGEINT | Additive | Sum of daily ranks. Average rank over any period = `SUM(rank_sum) / SUM(chart_days)` (do not average the weekly averages). |
| `avg_rank` | DOUBLE | Semi-additive | `rank_sum / chart_days`, 1 decimal, for this week only. |
| `presence_points` | HUGEINT | Additive | `SUM(201 − daily rank)`: 200 points for rank 1 down to 1 for rank 200; at most 1400 per week. **Q1's measure**: sum over the period, then rank the countries. |
| `is_complete_week` | BOOLEAN | Flag | The country's artist chart has all 7 days in this week. |
| `country_rank_for_artist_in_week` | BIGINT | Rank | 1 = the country where this artist's presence was strongest in this week. |

## `mart_song_chart_lifespan`
**Grain: one row per song × country** for songs released on or after `start_date` (so their whole chart life is inside the data). Question: Q5 (how long songs stay on the chart). Use rows with `is_still_charting = FALSE` for "typical" lengths, and medians rather than averages.

| Column | Type | Key / measure | Description |
|---|---|---|---|
| `song_id` | VARCHAR | FK → `dim_song.song_id` | Song. |
| `country_code` | VARCHAR | Degenerate dim | Market or `'global'`. |
| `track_name`, `artist_names` | VARCHAR | Attribute | From the song's best-ranked row in this country. |
| `release_date` | DATE | Attribute | Earliest of the source `release_date` and the song's first chart entry anywhere. |
| `first_chart_date`, `last_chart_date` | DATE | Measure | First and last day on this country's chart. |
| `chart_days` | BIGINT | Additive | Days actually on the chart (gaps excluded). |
| `best_rank` | INTEGER | Semi-additive | Best rank in this country. |
| `days_release_to_entry` | BIGINT | Measure | `first_chart_date − release_date`. |
| `days_release_to_exit` | BIGINT | Measure | `last_chart_date − release_date + 1` (release day is day 1). |
| `is_still_charting` | BOOLEAN | Flag | The song is on the chart on the country's latest data day, so the run is not finished. |

## `dim_date` · **static**
**Grain: one calendar day**, from the Monday of the first chart week to the Sunday of the last chart week (both chart tables).

SCD justification: a calendar never changes. It deliberately holds **no** current-date-dependent flags: "this week" is resolved at query time (for example `MAX(week_start)`), otherwise a column would go stale between rebuilds.

| Column | Type | Description |
|---|---|---|
| `date_key` | DATE | **PK.** The day itself. Weekly facts join with `week_start = date_key`. |
| `year`, `quarter`, `month` | INTEGER | Calendar year, quarter 1–4, month 1–12. |
| `month_name` | VARCHAR | English month name. |
| `iso_year` | INTEGER | ISO-8601 week-numbering year. Differs from `year` around 1 January. |
| `iso_week` | INTEGER | ISO-8601 week number, 1–53. |
| `iso_day_of_week` | BIGINT | 1 = Monday … 7 = Sunday. |
| `day_name` | VARCHAR | English weekday name. |
| `week_start` | DATE | Monday of this day's ISO week. |
| `week_end` | DATE | Sunday of this day's ISO week. |

## `dim_song` · **SCD Type 1**
**Grain: one song** (`song_id` = the song's main URI).

SCD justification: Type 1. A corrected title or release date should overwrite the old value; the old value has no analytical meaning and nobody asks what a song was called last year.

| Column | Type | Description |
|---|---|---|
| `song_id` | VARCHAR | **PK**, natural key. Unique, not null. |
| `track_name` | VARCHAR | Song title. Usually NULL for unknown-song members. |
| `artist_names` | VARCHAR | `|`-separated artist names, primary artist first. Display only: `dim_artist` cannot be joined through names. |
| `artist_uris` | VARCHAR | `|`-separated artist URIs, aligned with `artist_names`. NULL for unknown-song members. |
| `label` | VARCHAR | Record label from `songs.csv` (unknown songs: from the best-ranked chart row). NULL if none. |
| `release_date` | DATE | Source release date: the album the track is currently linked to, so often later than the first release. For the real first release use `mart_song_chart_lifespan.release_date`. Unknown songs: the earliest chart-row release date. |
| `uri_count` | BIGINT | Number of URIs in `all_uris` (1 for unknown songs). |
| `is_unknown_song` | BOOLEAN | TRUE for a member created from the charts because `songs.csv` has no row for that URI. |

## `dim_artist` · **SCD Type 1**
**Grain: one artist URI.**

SCD justification: Type 1. Only `artist_uri` and `artist_name`; a respelling is a correction, not a business event. Listener numbers from `artists.csv` are left out on purpose: they are a one-day snapshot and are measures, not attributes.

| Column | Type | Description |
|---|---|---|
| `artist_uri` | VARCHAR | **PK**, natural key. Unique, not null. |
| `artist_name` | VARCHAR | From `artists.csv`; for unknown artists the latest chart spelling. **Not unique**: 329 names map to several artists. Always filter and group by `artist_uri`. |
| `is_unknown_artist` | BOOLEAN | TRUE for an artist on the chart that is missing from `artists.csv`. |

## `dim_label` · **SCD Type 1**
**Grain: one normalised label** (`label_key`), built from the labels of `dim_song`. Songs without a label have no row here.

SCD justification: Type 1. The key is a normalised string; a rename is a correction, not a business event that should be logged.

| Column | Type | Description |
|---|---|---|
| `label_key` | VARCHAR | **PK.** `LOWER(TRIM(label))`; spellings that differ only by case or spaces are one label. Unique, not null. |
| `label_name` | VARCHAR | Most frequent spelling, for display (ties: alphabetical). |
| `label_group` | VARCHAR | Heuristic parent label: the text before the first `/` (for example `"Sony Music Latin/Duars Entertainment"` becomes `"Sony Music Latin"`). |
| `song_count` | HUGEINT | Number of songs with this label. |

> `label_group` is a **heuristic, not a curated hierarchy.** It merges a stated sub-label into its parent but cannot know that "Columbia" belongs to Sony. A definitive label ranking needs a proper parent mapping, which this source does not provide.

---

# 5. Data quality checks

| Where | Check |
|---|---|
| **Airflow** `check_raw_quality` (before dbt runs) | The window is not empty; key columns are not NULL; no chart position (date, country, rank) repeats; ranks are within 1–200; song and artist URIs are not duplicated. A failure stops the run, so dbt does not start. |
| **dbt, staging** | `not_null` on `chart_date`, `country_code`, `chart_rank`, `track_uri` / `artist_uri`, `entry_date` (artist chart); `unique` and `not_null` on `stg_songs.track_uri` and `stg_artists.artist_uri`. |
| **dbt, intermediate** | `unique` on `int_song_uri_map.track_uri`; grain uniqueness (concatenated key) on every int model, including (`chart_date`, `country_code`, `chart_rank`) on both daily models; `not_null` on `song_id`; `unique` and `not_null` on `int_song`, `int_artist`, `int_date`, `int_label` keys; `not_null` on `int_date.week_start`. |
| **dbt, gold** | `unique` and `not_null` on `dim_song.song_id`, `dim_artist.artist_uri`, `dim_date.date_key`, `dim_label.label_key`; `relationships` from each fact to its dimensions (see the table in section 4). |
| **dbt, reconciliation** (singular tests, `dbt_project/tests/`) | `assert_songs_weekly_rows_match_daily`: every (week, country, song) combination of the daily layer reaches `mart_songs_weekly`. `assert_songs_weekly_streams_match_daily`: streams per week and country agree between the daily layer and the weekly fact. `assert_artist_presence_matches_daily`: artist counts and presence points agree per week and country. `assert_week_start_is_monday`: weekly models use Monday week starts. |
| **dbt, source assumptions** | `assert_duplicate_song_rows_have_equal_streams` (the assumption behind the deduplication; fails if a new dataset version breaks it). `assert_chart_uris_are_mapped` (warning only): more than 100 chart URIs missing from the song mapping. |

Reconciliation tests exist because row-level tests cannot notice data that silently disappears between layers (an earlier version of the model lost about 15% of streams without any ordinary test failing).

---

# 6. Lineage

```
raw.songs ─────────► stg_songs ──► int_song_uri_map ─┐
raw.charts_songs_daily ► stg_charts_songs_daily ──────┴► int_charts_songs_daily ─┬► int_songs_weekly ────────► mart_songs_weekly
                                                       │                         ├► int_song_chart_lifespan ─► mart_song_chart_lifespan
raw.artists ───────► stg_artists ──┐                   │
raw.charts_artists_daily ► stg_charts_artists_daily ► int_charts_artists_daily ─┬► int_artist_country_weekly_presence ─► mart_artist_country_weekly_presence
                                                                                └► int_artist ──► dim_artist
stg_songs + int_charts_songs_daily ► int_song ──► dim_song ;  int_song ► int_label ──► dim_label
```

`int_date` reads the first and last chart dates of **both** daily models (`int_charts_songs_daily` and `int_charts_artists_daily`) and feeds `dim_date`. `int_artist` also reads `int_charts_artists_daily`, to add chart artists missing from `artists.csv`.

The exact graph is generated by `dbt docs generate` (see the README).
