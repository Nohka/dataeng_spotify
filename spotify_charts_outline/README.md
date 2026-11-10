# Spotify Charts Warehouse

A dbt project that turns daily Spotify Top-200 chart files into a small, tidy warehouse you can actually ask questions of: *What's the hottest song in Estonia this week? Where is an artist strongest? Which labels dominated last quarter?*

It runs on **PostgreSQL 16** and uses the Kaggle dataset **"Spotify Charts Daily Updated"** as its source.

---

## The idea in one minute

Spotify publishes a Top-200 chart for every country, every day. That's a lot of rows (almost 4 million song rows since January 2026) and the raw files are messy: songs have several URIs, the same artist sometimes appears twice on one day's chart, labels go missing, and release dates are unreliable.

This project cleans all of that up in three steps and ends with a **star schema**: two weekly fact tables surrounded by four dimension tables. Analysts query the star schema and never touch the raw data.

```
raw CSVs  ──►  staging  ──►  intermediate  ──►  marts (star schema)
 (as-is)      (clean types)  (joins, keys,      (what you query)
                              metrics)
```

## The data model

Everything is measured **per ISO week, per country**. A week starts on Monday and is identified by the Monday's date.

```
                  dim_date
                 /        \
     fact_song_weekly   fact_artist_weekly
        /        \              |
   dim_song   dim_label     dim_artist
```

| Table | One row per… | What it's for |
|---|---|---|
| `fact_song_weekly` | week × country × song that charted | Streams, best rank, growth vs. last week, a "heat score", weeks since release |
| `fact_artist_weekly` | week × country × artist that charted | Days on chart, best and average rank, a "presence score" |
| `dim_song` | song | Title, main artist, release date |
| `dim_artist` | artist | Name |
| `dim_label` | record label | Name plus a rough parent-label grouping |
| `dim_date` | calendar day | Year, quarter, month, ISO week, week start/end |

The full column-by-column reference lives in **[DATA_DICTIONARY.md](DATA_DICTIONARY.md)**.

### The two custom scores

- **Heat score** (songs): `weekly streams × (1 + growth vs. last week)`, with growth clamped between -50% and +100%. Big songs stay on top, but a song that's surging gets a boost of up to 2×.
- **Presence score** (artists): every chart day earns `201 − rank` points (200 for #1, 1 for #200), summed over the week and divided by 200. Read it as "equivalent days at #1".

## How the project is organised

```
models/
  staging/        1:1 with the raw files; only casts, renames and null clean-up
  intermediate/   key resolution, daily chart rows, weekly metrics
  marts/          the star schema (facts + dimensions)
tests/            custom checks, mostly "did we lose any data on the way?"
demo_queries/     five example questions answered in SQL
DATA_DICTIONARY.md
```

**Staging** is deliberately boring: no joins, no filters. **Intermediate** is where the real work happens: mapping every release-specific song URI to one canonical song, normalising label names, and building the daily and weekly chart models. **Marts** are the final tables.

## Messy-data decisions worth knowing about

The source has quirks, and the model handles each one on purpose:

- **One song, many URIs.** Re-releases get their own URIs. They're mapped to a single canonical song so a song's history isn't split.
- **Duplicates on the same day.** Some artists (and a few songs) hold two chart positions in one day. Rank is part of the daily grain, and weekly counts use distinct days so nothing is double-counted.
- **Missing labels.** About 43,000 chart rows have no label. They point to an explicit `(unknown)` label, so no row is ever dropped.
- **Unknown songs.** Songs that chart but are missing from the song file get a placeholder row in `dim_song` (`is_unknown_song = true`).
- **Release dates.** The song file only holds the *latest* re-release date, so the model takes the earliest date seen anywhere. A few hundred rows still show a song charting slightly *before* its recorded release, which is a source limitation.
- **Artist names aren't unique.** 329 names belong to more than one artist. Always group by `artist_uri`, not by name.
- **The `global` chart** is a pseudo-country whose streams overlap the real countries. Leave it out when adding up across countries.

## Data quality

Tests run at every layer: uniqueness, not-null, allowed values, and foreign keys. On top of that, a few custom tests act as safety nets:

- **Stream reconciliation:** every stream in the daily layer must show up in the weekly fact.
- **Row reconciliation:** every week/country/song (and artist) combination must survive into the facts.
- **Monday check:** the calendar must start on a Monday, otherwise the first week's key would point at nothing.

These exist because earlier bugs once silently dropped ~15% of streams without any ordinary test noticing.

## Refreshing the data

Source files are refreshed daily. The two daily chart models are **incremental** and re-load the most recent 7 days on each run; everything else is rebuilt in full. Data starts on **2026-01-05**, set by the `chart_start_date` variable.

## Try it out

The `demo_queries/` folder answers five real questions against the marts:

| File | Question |
|---|---|
| `q1_hottest_song_estonia_this_week.sql` | What's the hottest song in Estonia this week? |
| `q2_artist_strongest_country.sql` | In which countries is a given artist strongest? |
| `q3_labels_most_top10_songs_last_quarter.sql` | Which labels had the most Top-10 songs last quarter? |
| `q4_breakout_songs_this_week.sql` | Which songs broke out this week? |
| `q5_chart_longevity_after_release.sql` | How long do new songs stay on the chart after release? |

## Known limitations

- Label grouping is a **heuristic** (it uses the text before the first `/`). It can't know that, say, Columbia belongs to Sony, so treat label rankings as approximate.
- Artist listener numbers exist in staging but aren't used downstream.
- Everything is Type 1 (overwrite): the warehouse doesn't keep history of renamed songs, artists or labels.
