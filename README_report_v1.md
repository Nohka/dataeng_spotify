# Music trends for radio hosts: report v1 companion

Intended repository: https://github.com/Nohka/dataeng_spotify

This package accompanies `music_trends_3_page_report.docx`. It proposes a smaller,
self-contained version 1 than the earlier expanded model. It does not assume that
these files already exist in the repository, and it has not been pushed to GitHub.

## Contents

- `sql/01_core_schema.sql`: one daily-track fact, four dimensions and three support tables.
- `sql/02_metric_views.sql`: complete-week checks, Hotness, Momentum, current locality and comparable reporting windows.
- `sql/03_demo_queries.sql`: the five business questions, including all first-place Hotness ties.
- `docs/data_dictionary_v1.md`: readable core dictionary.
- `docs/data_dictionary_v1.json`: column-level structured dictionary.

The report is the editable working document. The assignment calls for a final
`Report.pdf` of at most three pages. Export the completed DOCX to PDF and check its
pagination after replacing the team's placeholders.

## Before submission

1. Agree the contribution percentages, ensure they total 100%, and replace the
   four `[__%]` placeholders. Roles follow the team's supplied draft, not commit counts.
2. Add shared links to every AI/LLM conversation used; the report has an explicit
   `[ADD CHAT URLS]` field. Check that links are accessible to the assessor.
3. Profile the actual source extracts. Each of the two independent datasets must
   meet the 1,000-row / 8-column requirement. Record observed counts, versions,
   extract dates, relevant missingness and the chart date/market coverage here.
   The package does not claim that raw Kaggle or MusicBrainz extracts were downloaded.
4. Verify the actual CSV headers and Spotify chart-to-entity URI mappings. Adapt
   ingestion mappings rather than silently joining by title or artist name.
5. Seed and document the full agreed European comparison panel, including markets
   with missing charts. A missing country must not disappear from the denominator.
6. Review these additions alongside the current repository. Retain one authoritative
   v1 schema/dictionary; clearly label any earlier, larger model as an extension.

Suggested source-profile record (fill from actual data, not estimates):

| Source extract | Version / extraction date | Rows | Columns | Coverage / match rate |
|---|---|---:|---:|---|
| Kaggle daily track chart extract | Record actual value | Record actual value | Record actual value | Dates, markets, chart completeness |
| MusicBrainz artist extract | Record actual value | Record actual value | Record actual value | Distinct artists, missing area, accepted Spotify matches |

## Database workflow

These are proposed PostgreSQL scripts, not a running pipeline. No source data is
included. They have not been executed against a PostgreSQL server or validated
against the actual music extracts.

Run the schema once on an empty `music_report_v1` schema, populate the dimensions,
bridge, locality reviews, facts and load ledger through the planned ETL process,
and then run the views and demo queries. The scripts use a separate namespace to
avoid changing the earlier `music` schema. Schema creation is not an idempotent
migration for pre-existing tables; inspect your database first.

The workflow order is:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/01_core_schema.sql
# Populate and validate the warehouse using the team's ingestion/ETL pipeline.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/02_metric_views.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/03_demo_queries.sql
```

In query 5, replace the intentional `CAST(NULL AS TEXT)` parameter with a quoted
real Spotify artist URI present in `dim_artist`. The default returns no rows,
rather than pretending a particular artist was selected.

## Metric and modelling rules

Reporting weeks are Monday-Sunday. Preserve UTC source chart dates; this project
week is distinct from Spotify's native Friday-Thursday chart week. Use decimal
arithmetic for Hotness: `100.0/7.0 * SUM((201.0-chart_rank)/200.0)`.

A source-reconciled, complete week must have seven complete date/market ledger
rows. A count of 200 chart rows is not sufficient evidence of completeness.
Verified off-chart days add zero *visibility*, but do not establish zero streams.
Missing stream values stay NULL. `observed_chart_streams` is only a sum of streams
reported for chart appearances, not the track's entire weekly Spotify audience.

Momentum requires the immediately preceding calendar week to be complete. For a
track absent from that verified prior chart week, prior visibility is zero. A
missing prior chart week instead produces NULL Momentum. The summary view lists
tracks appearing in the current week; a separate full-outer-join view would be
needed for an exit-only report.

For cross-country comparisons, use weeks complete in every member of the fixed
European panel. The comparison window spans 12 calendar weeks ending at the latest
common complete week. Incomplete weeks inside the window are excluded and the
queries display the count of common complete weeks. They are not replaced by
older weeks. A one-week sample must not be described as twelve weeks of evidence.

For Top-20 Consistency, count each qualifying label-market-week or artist-week
once. The denominator includes eligible weeks without a hit. Artist presence
can legitimately overlap across collaborations; never add artist presence counts
and call the result a unique track count. Query 5 counts distinct artist-market-days
using the same common weeks for every country, not unique listeners.

`record_label_current` and `artist_locality` use current attribution. Preserve raw
snapshots and review evidence, but do not claim historical label ownership or
historical artist nationality. Type 2 histories can be added later when dated
source evidence and the actual reporting requirement justify them.

Rule `v1` makes a track local when at least one credited artist has a reviewed
primary association with the market. Resolve MusicBrainz areas to countries and
review ambiguous identity matches. Area is not citizenship or recording language.
The summary returns `not_local` only when there is at least one credited artist
and every credited artist has a reviewed `not_local` result under rule v1;
otherwise unresolved cases remain `unknown`.

AI-origin labels, weekly albums, separate artist charts and monthly audience
snapshots are out of scope for the minimal v1 report. AI evidence would need a
recording-level source and an assessment/provenance model, not a guessed Boolean.

## Suggested acceptance tests

- No duplicate fact grain or bridge pairs; every FK resolves.
- Ranks are between 1 and 200; known stream values are non-negative.
- Seven days at rank 1 give Hotness 100; seven days at rank 200 give 0.5.
- A single day at rank 1 in a verified complete week gives 100/7.
- A partial/missing day suppresses the complete-week score for that market.
- A missing prior week gives NULL Momentum, not a zero baseline.
- One collaboration with two credited local artists still produces one track row.
- Missing locality evidence remains unknown; known statuses require a review time
  and a non-blank evidence URL.
- GLOBAL is not in the European country panel and is not added to country totals.
- An artist with several charting tracks on the same day gets one presence day.
- Tied leading tracks are retained by both Hotness queries.

## Sources

- Assignment requirements and initial roles: team-supplied `part1_submission.docx`.
- https://www.kaggle.com/datasets/gonzalopezgil/spotify-charts-daily-updated/data
- https://musicbrainz.org/doc/Artist
- https://musicbrainz.org/doc/MusicBrainz_API
- https://support.spotify.com/bn-en/artists/article/understanding-spotify-charts/

AI/LLM use and source-profile results should be completed by the team before submission.
