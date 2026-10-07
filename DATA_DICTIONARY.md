# Data Dictionary — Spotify Charts Warehouse

**Project:** Spotify Charts dimensional model (`spotify_dbt`)
**Warehouse / dialect:** PostgreSQL 16
**Ingestion window:** chart data from **2026-01-05** (the first Monday of 2026) onward.
**Refresh:** source CSVs are refreshed daily, the two daily chart models are incremental and replace the last 7 day-partitions on each run. Everything else rebuilds in full.

## Conventions

| Topic | Rule |
|---|---|
| Keys | Natural keys everywhere (`track_uri`, `artist_uri`, `label_name_norm`). `dim_date` is the one exception: integer `date_key` in `yyyymmdd` form. |
| Week identity | Weekly facts carry `week_date_key` = the `date_key` of the ISO-week **Monday**. It joins to `dim_date.date_key`, so `dim_date` plays a *week* role for the facts and a *day* role elsewhere. |
| Unknown members | `dim_label` has an explicit `'(unknown)'` row and `dim_song` has `is_unknown_song` members, so no fact row carries a NULL foreign key and no chart row is ever dropped for a missing dimension member. |
| Additivity | `weekly_streams`, `stream_gain_wow`, `days_*`, `rank_sum`, `rank_points` are additive. `best_rank`, `avg_rank` are **semi-additive** — never SUM them. `heat_score`, `presence_score`, `stream_growth_wow` are **ratios/scores** — never SUM them across rows. |

---

# 1. Source layer — `raw` schema

Kaggle *Spotify Charts Daily Updated*. Loaded as-is by file load; every column is `text` in `raw` and cast in staging.

| Table | Grain | Rows (in window) | Notes |
|---|---|---|---|
| `raw.charts_songs_daily` | date × country × rank | 3,849,481 | Daily Top-200 song chart with streams. |
| `raw.charts_artists_daily` | date × country × rank | 3,654,126 | Daily Top-200 artist chart. No streams. |
| `raw.songs` | `track_uri` | 215,184 | Song metadata. `all_uris` lists release-specific URIs. |
| `raw.artists` | `artist_uri` | 73,833 | Artist metadata. Listener columns unused downstream. |

### Known source characteristics

| Characteristic | Measured | Handling |
|---|---|---|
| Same artist listed twice in one day/country | 3,436 cases, 57 artists | `rank` is part of `int_artist_chart_daily`'s grain; the weekly model collapses each day to the artist's best rank. |
| Same song holding two chart positions in one day | 192 day/country/uri cases | `rank` is part of `int_song_chart_daily`'s grain, day counts use `count(distinct chart_date)`, streams are summed across both positions. |
| Missing label | 43,245 daily rows (full history) | Resolved to the `'(unknown)'` dimension member. |
| `songs.csv` release date is the *latest* re-release | — | `int_song` takes the earliest date across `songs.csv` and all chart rows. |
| Artist names are not unique | 329 names map to >1 artist | Always key on `artist_uri`. |

---

# 2. Staging layer — `analytics_staging` (views)

1:1 with the source files. Casts, renames, `-1 → NULL` on `previous_rank`, `'' → NULL` on
labels. **No joins, filters or derived columns.**

### `stg_spotify__charts_songs_daily`
Grain: `chart_date` × `country_code` × `rank`.

| Column | Type | Null | Description |
|---|---|---|---|
| `chart_date` | DATE | no | Chart day. |
| `country_code` | VARCHAR | no | ISO-2 lower-case market, or `'global'`. |
| `rank` | INTEGER | no | Chart position, 1–200. |
| `track_uri_raw` | VARCHAR | no | Release-specific Spotify track URI **as published**; resolved to a canonical URI downstream. |
| `track_name` | VARCHAR | yes | Song title as published on the chart row. |
| `artist_names` | VARCHAR | yes | Pipe-separated artist names. |
| `artist_uris` | VARCHAR | yes | Pipe-separated artist URIs. |
| `label_name` | VARCHAR | yes | Record label, trimmed; NULL when absent. |
| `streams` | BIGINT | yes | Streams that day in that market. |
| `peak_rank` | INTEGER | yes | Best position reached to date. |
| `previous_rank` | INTEGER | yes | Position the previous day; source `-1` → NULL. |
| `days_on_chart` | INTEGER | yes | Source's own running day count. |
| `consecutive_days` | INTEGER | yes | Source's own consecutive-day count. |
| `entry_status` | VARCHAR | yes | `NEW_ENTRY` \| `MOVED_UP` \| `MOVED_DOWN` \| `NO_CHANGE` \| `RE_ENTRY`. |
| `entry_rank` | INTEGER | yes | Position on first entry. |
| `entry_date` | DATE | yes | Date of first entry. |
| `peak_date` | DATE | yes | Date the peak was reached. |
| `release_date` | DATE | yes | Release date **as published at the time this row was charted**. Used by `int_song` to recover the original release date. |

### `stg_spotify__charts_artists_daily`
Grain: `chart_date` × `country_code` × `rank`. Same columns as above except
`streams`, `track_*`, `label_name`, `release_date`, `artist_uris` but adding:

| Column | Type | Null | Description |
|---|---|---|---|
| `artist_uri` | VARCHAR | no | Spotify artist URI. Natural key; no alias resolution needed. |
| `artist_name` | VARCHAR | yes | Artist name as published on the chart row. |

### `stg_spotify__songs`
Grain: `track_uri` (unique).

| Column | Type | Null | Description |
|---|---|---|---|
| `track_uri` | VARCHAR | no | Canonical Spotify track URI. |
| `track_name` | VARCHAR | yes | Song title. |
| `artist_names` | VARCHAR | yes | Pipe-separated artist names, primary artist first. |
| `artist_uris` | VARCHAR | yes | Pipe-separated artist URIs, aligned with `artist_names`. |
| `label_name` | VARCHAR | yes | Record label, trimmed. Not used downstream, the label comes from the chart rows so there is one label path. |
| `release_date` | DATE | yes | Release date. |
| `all_uris` | VARCHAR | yes | Pipe-separated release-specific URIs, always contains `track_uri` itself. |

### `stg_spotify__artists`
Grain: `artist_uri` (unique).

| Column | Type | Null | Description |
|---|---|---|---|
| `artist_uri` | VARCHAR | no | Spotify artist URI. |
| `artist_name` | VARCHAR | yes | Display name. **Not unique.** |
| `monthly_listeners` | BIGINT | yes | Number of monthly listeners. |
| `listener_rank` | INTEGER | yes | Rank of the artist by monthly listeners. |
| `listener_peak_rank` | INTEGER | yes | Peak rank of the artist by monthly listeners. |
| `listener_peak_listeners` | BIGINT | yes | Peak number of monthly listeners. |

---

# 3. Intermediate layer — `analytics_intermediate`

All joins, key resolution, and metrics are created here in three sub-layers.

## Layer 1 — key resolution and conformed dimensions

| Model | Materialisation | Grain | Purpose |
|---|---|---|---|
| `int_song_uri_aliases` | table | `alias_uri` | Maps each release-specific URI to its canonical `track_uri`. |
| `int_song` | table | `track_uri` | Int table for the final song dimension. |
| `int_label` | table | `label_name_norm` | Int table for the final Label dimension. |
| `int_artist` | table | `artist_uri` | Artist dimension for artists that charted in the window. |
| `int_date` | table | `full_date` | Generated calendar. No upstream model. |

### `int_song_uri_aliases`
| Column | Type | Null | Description |
|---|---|---|---|
| `alias_uri` | VARCHAR | no | A release-specific track URI as it appears on a chart row. **Unique.** |
| `track_uri` | VARCHAR | no | The canonical song this alias belongs to. |


## Layer 2 — daily chart rows with keys resolved

| Model | Materialisation | Grain |
|---|---|---|
| `int_song_chart_daily` | incremental, `delete+insert` on `chart_date` | chart day × country × canonical song × rank |
| `int_artist_chart_daily` | incremental, `delete+insert` on `chart_date` | chart day × country × artist × rank |

`unique_key` is `chart_date` alone so each run replaces whole **day partitions**. Needs to be partitioned by `chart_date` because otherwise the incremental run could create duplicates, when ranks change within the same day.


### `int_song_chart_daily`
| Column | Type | Null | Description |
|---|---|---|---|
| `chart_date` | DATE | no | Chart day. |
| `country_code` | VARCHAR | no | ISO-2 market or `'global'`. |
| `track_uri` | VARCHAR | no | Canonical song, alias-resolved. FK → `int_song`. |
| `label_name_norm` | TEXT | no | `lower(label)`, or `'(unknown)'`. FK → `int_label`. |
| `rank` | INTEGER | no | 1–200. |
| `streams` | BIGINT | yes | Streams that day. |
| `is_top10` | BOOLEAN | no | `rank <= 10`. |
| `is_top20` | BOOLEAN | no | `rank <= 20`. |

### `int_artist_chart_daily`
| Column | Type | Null | Description |
|---|---|---|---|
| `chart_date` | DATE | no | Chart day. |
| `country_code` | VARCHAR | no | ISO-2 market or `'global'`. |
| `artist_uri` | VARCHAR | no | FK → `int_artist`. |
| `rank` | INTEGER | no | 1–200. |
| `is_top20` | BOOLEAN | no | `rank <= 20`. |

## Layer 3 — weekly metric models

`int_song_chart_weekly` and `int_artist_chart_weekly` are **views**, their rows are
materialised once by the corresponding mart tables. Their columns are identical to
`fact_song_weekly` / `fact_artist_weekly` below, which is where they are documented.


---

# 4. Mart layer — `analytics_marts` (the star schema)

```
                  dim_date (week role)
                   /              \
     fact_song_weekly          fact_artist_weekly
      /      |                        |
dim_song  dim_label              dim_artist
```
Two **periodic snapshot** facts.


## `fact_song_weekly` — 717,593 rows
**Grain: one row per ISO week × country × canonical song in which the song charted.**

| Column | Type | Null | Key/Measure | Description |
|---|---|---|---|---|
| `week_date_key` | INTEGER | no | FK → `dim_date.date_key` | `yyyymmdd` of the ISO-week Monday. |
| `country_code` | VARCHAR | no | Degenerate dim | ISO-2 market or `'global'`. |
| `track_uri` | VARCHAR | no | FK → `dim_song.track_uri` | Canonical song. |
| `label_name_norm` | TEXT | no | FK → `dim_label.label_name_norm` | `'(unknown)'` when the chart row carried no label. |
| `weekly_streams` | NUMERIC | no | Additive | Sum of daily streams. 0 rather than NULL when no day carried a count. |
| `days_with_streams` | BIGINT | no | Additive | 0–7. Days that actually carried a stream count. **Less than `days_on_chart` means `weekly_streams` understates the total.** |
| `prev_week_streams` | NUMERIC | yes | Additive | `weekly_streams` of the immediately preceding week, NULL after a gap. |
| `stream_gain_wow` | NUMERIC | no | Additive | Absolute week-over-week gain. A new entry gains its full week. **Q4's ranking measure.** |
| `days_on_chart` | BIGINT | no | Additive | 1–7. Distinct days the song charted. |
| `days_top10` | BIGINT | no | Additive | 0–7. Distinct days ranked 1–10. **Q3's Top-10 test.** |
| `best_rank` | INTEGER | no | Semi-additive | 1–200. Best position that week. Never SUM. |
| `charted_prev_week` | BOOLEAN | no | Flag | True when the song also charted the immediately preceding ISO week. |
| `prev_week_best_rank` | INTEGER | yes | Semi-additive | `best_rank` of the preceding week; NULL after a gap, so a re-entry never compares against a stale week. |
| `stream_growth_wow` | NUMERIC | yes | Ratio | `weekly_streams / prev_week_streams - 1`. NULL after a gap. Never SUM. |
| `heat_score` | NUMERIC | no | Score | `weekly_streams × (1 + growth clamped to [-0.5, +1.0])`. **Q1's ranking measure.** Streams stay dominant; momentum can at most double a song's weight. Never SUM. |
| `chart_week_no` | BIGINT | no | Sequence | 1 for the song's first charted week in that country, then 2, 3 … Counts **charted** weeks, not calendar weeks. |
| `weeks_since_release` | INTEGER | yes | Attribute | Whole ISO weeks from the song's **release week** to this chart week; **0 in the release week**. NULL when no plausible release date is known. Negative on 222 rows (0.03%, range -1 to -9) that charted before any release date in the source — a source limitation, not a modelling error; Q5 filters `BETWEEN 0 AND 12`. |

## `fact_artist_weekly` — 615,537 rows
**Grain: one row per ISO week × country × artist in which the artist charted.** 

| Column | Type | Null | Key/Measure | Description |
|---|---|---|---|---|
| `week_date_key` | INTEGER | no | FK → `dim_date.date_key` | `yyyymmdd` of the ISO-week Monday. |
| `country_code` | VARCHAR | no | Degenerate dim | ISO-2 market or `'global'`. |
| `artist_uri` | VARCHAR | no | FK → `dim_artist.artist_uri` | Artist. |
| `days_on_chart` | BIGINT | no | Additive | 1–7. Distinct days charted (same-day duplicates collapsed to the best rank). |
| `days_top20` | BIGINT | no | Additive | 0–7. Distinct days ranked 1–20. |
| `best_rank` | INTEGER | no | Semi-additive | 1–200. Best position that week. Never SUM. |
| `avg_rank` | NUMERIC | no | Semi-additive | Mean daily position that week. **Do not average across weeks** — use `rank_sum / days_on_chart`. |
| `rank_sum` | BIGINT | no | Additive | Sum of daily positions, so a day-weighted mean rank can be rebuilt across any span. |
| `rank_points` | BIGINT | no | Additive | 1–1400. `sum(201 - daily rank)`: 200 points for rank 1 down to 1 for rank 200. Non-saturating. 1400 = rank 1 on all seven days. |
| `presence_score` | NUMERIC | no | Score | `rank_points / 200`, i.e. "equivalent rank-1 days". **Q2's ranking measure.** Additive across weeks. |

## `dim_date` — 644 rows · **Static**
**Grain: one calendar day**, from `chart_start_date` to the Sunday one year ahead.

SCD justification: a calendar never changes. Deliberately holds **no**
`current_date`-dependent flags, "this week" is resolved at query time, otherwise the
column would go stale between rebuilds.

| Column | Type | Null | Description |
|---|---|---|---|
| `date_key` | INTEGER | no | **PK.** `yyyymmdd`. |
| `full_date` | DATE | no | The day itself. Unique. |
| `year` | INTEGER | no | Calendar year. |
| `quarter` | INTEGER | no | Calendar quarter, 1–4. |
| `month` | INTEGER | no | Calendar month, 1–12. |
| `iso_year` | INTEGER | no | ISO-8601 week-numbering year. Differs from `year` around 1 January. |
| `iso_week` | INTEGER | no | ISO-8601 week number, 1–53. |
| `week_start_date` | DATE | no | Monday of this day's ISO week. |
| `week_end_date` | DATE | no | Sunday of this day's ISO week. |
| `week_date_key` | INTEGER | no | `yyyymmdd` of `week_start_date`. This is what the weekly facts carry. |


## `dim_song` — 215,193 rows · **SCD Type 1**
**Grain: one canonical song.**

SCD justification: Type 1. A corrected title or release date should overwrite, the old
value has no analytical meaning and nobody asks "what was this song called last year".

| Column | Type | Null | Description |
|---|---|---|---|
| `track_uri` | VARCHAR | no | **PK**, natural key. Canonical Spotify track URI. |
| `track_name` | VARCHAR | yes | Song title. NULL for unknown-song members. |
| `primary_artist_name` | TEXT | yes | First name in `artist_names`. **Display only — not a key.** `dim_artist` cannot be joined through it. |
| `release_date` | DATE | yes | Earliest release date across `songs.csv` and all chart rows. NULL when unknown or implausible (outside 1900-01-01 … +1 year). |
| `is_unknown_song` | BOOLEAN | no | True for a member synthesised from the charts because `songs.csv` has no row for that URI. 9 such members in the current data. |

## `dim_artist` — 11,060 rows · **SCD Type 1**
**Grain: one artist that charted inside the window.**

SCD justification: Type 1. Only `artist_uri` and `artist_name`, a respelling is a
correction, not an event.

| Column | Type | Null | Description |
|---|---|---|---|
| `artist_uri` | VARCHAR | no | **PK**, natural key. |
| `artist_name` | VARCHAR | no | From `artists.csv` when present, otherwise the latest chart spelling. **Not unique**, 329 names map to several artists (five distinct "Kali" profiles). Always filter and group by `artist_uri`. |

## `dim_label` — 7,933 rows · **SCD Type 1**
**Grain: one normalised label name.**

SCD justification: Type 1. The key is a normalised string, a rename is a correction, not
a business event that should be logged.

| Column | Type | Null | Description |
|---|---|---|---|
| `label_name_norm` | TEXT | no | **PK.** `lower(btrim(label))`, or the literal `'(unknown)'`. |
| `label_name` | TEXT | no | Most frequent raw spelling, for display. |
| `label_group_norm` | TEXT | no | Heuristic parent key: the segment before the first `/`, lower-cased. Rolls `"Sony Music Latin/Duars Entertainment"` up to `"sony music latin"`. |
| `label_group` | TEXT | no | Display form of `label_group_norm`. |

> `label_group` is a **heuristic, not a curated hierarchy.** It merges a stated
> sub-label into its parent but cannot know that "Columbia" belongs to Sony. A definitive label ranking needs a proper parent mapping,
> which this source does not provide.

---

# 5. Data quality checks

We are planning to have different type of tests for each layer of the data pipeline, some examples are below:

| Layer | Checks |
|---|---|
| staging | `unique` on (`chart_date`, `country_code`, `rank`) for both chart files; `not_null` on keys; `accepted_values` on `entry_status`; `unique` on `track_uri` / `artist_uri`. |
| int layer 1 | `unique` + `not_null` on every dimension key; `alias_uri` unique; `release_date >= 1900-01-01`. |
| **reconciliation** | `assert_song_streams_reconcile` — every stream in `int_song_chart_daily` reaches `fact_song_weekly` Plus row-count reconciliation on both fact paths. |