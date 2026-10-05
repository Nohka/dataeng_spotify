# Music Trends for Radio Hosts

A data engineering project to provide timely, geographically relevant music-trend insights for radio hosts and music editors, with transparent data coverage and quality limitations.

**Repository:** [Nohka/dataeng_spotify](https://github.com/Nohka/dataeng_spotify)  
**Current scope:** Part 1 - project design and documentation  
**Documentation baseline:** 2026-10-05

[Project progress and update log](PROJECT_LOG.md) | [Team](#team) | [Data sources](#data-sources) | [Data model](#data-model) | [Repository files](#repository-files)

## Project status

The current v1 proposal includes a business brief, architecture, dimensional model, data dictionary, metric definitions, five draft SQL queries and an editable three-page report. Source profiling and SQL execution have not yet been documented as verified results. Docker, Airflow, dbt and Superset describe a proposed pipeline, not services confirmed to be running.

The Part 1 brief does **not** require a working implementation. Its deliverables are a maximum-three-page `Report.pdf` and a GitHub repository containing a README and relevant SQL; pseudocode SQL is permitted. Validation of the design and source suitability remains necessary.

Use [PROJECT_LOG.md](PROJECT_LOG.md) for dated changes, decisions, evidence, blockers and reporting summaries. A drafted artifact is not automatically an approved or tested deliverable.

## Team

Working responsibilities follow the original project draft. They identify review areas, not proof of who completed each historical task. Record actual contributions in the project log and agree the final percentages together.

| Team member | Working responsibilities | Final contribution |
|---|---|---|
| Kristel Saul | Business brief, stakeholders, KPIs and data architecture | To agree |
| Kadi-Liis Kivi | Dataset selection, demo SQL queries and initial dictionary support | To agree |
| Laura Jõgi | Dataset selection and tooling | To agree |
| Tarvo Metspalu | Data model and data dictionary | To agree |

Contribution percentages must total **100%** in the final report. Include research, design, reviews and documentation as well as code; do not infer contribution percentages from commit counts.

## Business questions

Radio hosts and music editors are the primary users. Artists, labels, managers and event organisers are secondary users.

| ID | Question addressed by the v1 design |
|---|---|
| Q1 | Which track has the highest Weekly Hotness in Estonia in the latest complete reporting week? |
| Q2 | Which qualifying local track has the highest Weekly Hotness in Estonia in that same week? |
| Q3 | Which currently attributed labels have the highest Top-20 Consistency across the selected European markets? |
| Q4 | Which artists have the highest Top-20 Consistency in Estonia? |
| Q5 | For a selected artist, which European market has the most distinct chart-presence days within a comparable reporting window? |

Draft queries are in `sql/03_demo_queries.sql`. Q5 concerns **chart presence**, not country-level unique listeners.

## Data sources

| Source | Planned use | Validation still to record |
|---|---|---|
| [Spotify Charts Daily Updated on Kaggle](https://www.kaggle.com/datasets/gonzalopezgil/spotify-charts-daily-updated/data) | Daily track-chart observations, with track and artist entity metadata | Actual file headers, source versions, row/column counts, chart dates, markets, completeness and identifier mappings |
| [MusicBrainz artist metadata](https://musicbrainz.org/doc/Artist) via the [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API) | Artist identity matching and geographic evidence for locality review | Extract size and attributes, accepted Spotify matches, missing geographic information and ambiguous matches |

The assignment requires **at least two distinct datasets, each with at least 1,000 rows and eight columns**. Measure the actual extracts; do not count warehouse-generated fields toward the source-column requirement. These thresholds have not yet been verified for the proposed extracts.

Maintain this source-profile register after acquisition:

| Extract | Version and extraction date | Raw rows | Source columns | Profile evidence |
|---|---|---|---|---|
| Kaggle daily track-chart extract | Not recorded | Not measured | Not measured | Pending |
| MusicBrainz artist extract | Not recorded | Not measured | Not measured | Pending |

Each profile should also record the source URL, retained filename/checksum, date and market coverage where applicable, duplicate and missing-value findings, and identity-match coverage. Preserve the original files and document cleaning separately. Record reuse permissions before redistributing source data; keep credentials out of the repository.

### Locality rule v1

A track is local to a market when **at least one credited artist has a reviewed primary association with that market**. Prefer explicit Spotify identity links and review ambiguous matches. Artist geographic association is not automatically citizenship, birthplace or recording language.

Store `local`, `not_local` or `unknown`, together with the evidence URL, review time and rule version. A track is `not_local` only when it has credited artists and all of them have reviewed `not_local` classifications under the applicable rule. Otherwise, unresolved cases remain `unknown`; missing evidence is not a negative finding.

### Scope boundaries

The minimal v1 covers daily track charts and reviewed artist localisation. Weekly albums, separate artist charts, monthly audience snapshots, airplay data and AI-origin assessment are possible extensions, not current implemented capabilities. AI status must not be guessed from chart behaviour; any future assessment requires recording-level evidence and a separate assessment model.

## Proposed architecture

```text
Kaggle chart files + MusicBrainz artist metadata
    -> scheduled file/API pulls (Airflow)
    -> retained raw snapshots and PostgreSQL staging
    -> cleaning, identity matching and tests (dbt)
    -> dimensional warehouse and metric views (PostgreSQL)
    -> radio-editor dashboards (Superset)
```

Docker is the proposed common service environment. The design calls for daily chart ingestion after source publication and weekly artist-metadata refreshes. Downstream reporting refreshes follow validation; failed or incomplete source loads remain visible as coverage gaps. These are planned frequencies, not a configured schedule.

## Data model

**Namespace:** `music_report_v1`  
**Fact grain:** one observed track appearance in one market on one UTC daily chart date.  
**Fact primary key:** `(date_key, market_key, track_key)`.

The minimal model has one fact, four dimensions and three supporting tables.

| Table | One row represents | History treatment |
|---|---|---|
| `fact_track_chart_daily` | One track-market-date chart observation | Daily measurement history |
| `dim_date` | One calendar date | Static |
| `dim_market` | One chart market | Static for the agreed v1 market panel |
| `dim_track` | One source track identity | Type 1: current descriptive metadata and label |
| `dim_artist` | One Spotify artist identity | Type 1: current names and accepted MusicBrainz matches |
| `bridge_track_artist` | One unique credited track-artist pair | Relationship table |
| `artist_locality` | One current artist-market review | Current classification; retain source evidence separately |
| `ops_chart_load_daily` | One expected market-date load status | Current load status; retain attempt-level manifests separately |

Date, market and track dimensions link to the fact. Tracks and artists connect through the bridge; artists and markets connect through locality reviews. Do not store pipe-separated foreign keys or mix daily tracks with weekly albums in the same fact table.

Historical chart results use **current supplied label metadata and current reviewed locality** in v1. They do not reconstruct historical label ownership or historical artist associations. Any future history model needs dated evidence and an explicit reporting requirement.

## Metrics and interpretation

Project reporting weeks are **Monday-Sunday**, retaining the source's UTC chart dates. The metrics below are project definitions, not official Spotify scores. Their detailed rules are preserved in the report-v1 companion.

| Metric | Definition |
|---|---|
| Weekly Hotness, 0-100 | `100.0 / 7.0 * SUM((201.0 - chart_rank) / 200.0)` over a track's appearances in a complete seven-day market week |
| Weekly Momentum | Current Weekly Hotness minus the immediately preceding calendar week's Hotness, only when both market weeks are complete |
| Top-20 Consistency, % | `100.0 * qualifying_market_weeks / eligible_market_weeks` within a fixed 12-calendar-week window; a label or artist qualifies with at least one associated daily Top-20 track |

Verified off-chart days contribute zero **visibility points**, not zero streams. An unavailable or partial chart must not be treated as an off-chart day. An absent track in a verified complete prior week has zero prior visibility; an unavailable prior week produces `NULL` Momentum.

Cross-country comparisons use weeks complete in every member of the fixed European panel. Incomplete weeks inside the 12-week window are excluded, not replaced with older weeks; report the actual eligible-week count. `GLOBAL` must not be included in country totals. The Estonia-only consistency query uses complete Estonian weeks.

Count each qualifying label-market-week or artist-week once. For Q5, several tracks by one artist on the same day count as one chart-presence day. Collaborations may contribute presence to several artists, but artist totals must not be added together and called unique track totals. Preserve tied leaders in Q1 and Q2.

## Repository files

The paths below are the intended v1 layout. The `sql/` and dictionary files were supplied in `music_trends_repo_companion.zip`; add or reconcile them with the repository before relying on the links. Put the existing editable report under `docs/` and add the final PDF only after review. This map is not a statement that those files have already been committed.

| File | Purpose |
|---|---|
| [README.md](README.md) | Project overview and current working assumptions |
| [PROJECT_LOG.md](PROJECT_LOG.md) | Dated project updates, decision register and reporting template |
| [sql/01_core_schema.sql](sql/01_core_schema.sql) | Draft v1 tables, keys and constraints |
| [sql/02_metric_views.sql](sql/02_metric_views.sql) | Draft complete-week, metric, locality and comparison-window views |
| [sql/03_demo_queries.sql](sql/03_demo_queries.sql) | Draft queries for Q1-Q5 |
| [docs/data_dictionary_v1.md](docs/data_dictionary_v1.md) | Human-readable v1 dictionary |
| [docs/data_dictionary_v1.json](docs/data_dictionary_v1.json) | Structured v1 dictionary |
| `docs/music_trends_3_page_report.docx` | Suggested location for the existing editable report |
| `docs/Report.pdf` | Suggested location for the final maximum-three-page submission |

Use the minimal `music_report_v1` model consistently across the report, SQL and dictionary. The earlier expanded `music` schema is a separate proposal, not an additional part of this v1. Retain it only when clearly labelled as an extension or earlier design. The root README replaces the companion's introductory `README_report_v1.md` as the project entry point.

### Optional SQL validation

There is no documented end-to-end runtime setup yet. To validate the supplied SQL, use a disposable PostgreSQL database with a configured `DATABASE_URL`. Inspect the target first: the table-creation script is **not** an idempotent migration for existing tables.

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/01_core_schema.sql
# Populate and validate source mappings, dimensions, bridge, locality,
# chart facts and the load ledger before expecting analytical results.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/02_metric_views.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/03_demo_queries.sql
```

These commands do not download or load data. Q5 intentionally uses `CAST(NULL AS TEXT)` until a real Spotify artist URI is selected. An empty database or an unselected artist does not demonstrate successful business-question validation. Record any execution evidence in the project log; execution is not claimed by this README.

## Quality and review checks

Proposed acceptance checks cover unique fact/bridge keys and valid foreign keys; ranks from 1 to 200; non-negative known streams; reviewed identity matches; and chart-load completeness reconciled with the source rather than inferred from a 200-row count.

Metric review examples: seven days at rank 1 should give Hotness 100; a partial chart week should suppress a final complete-week score; a missing previous week should give `NULL` Momentum; and a collaboration with two local artists should still yield one track observation. These are checks to perform, not recorded passes.

For Part 1, also review consistency across the business questions, dictionary, relationships, SCD explanations and SQL. Note which checks were performed as a design review and which, if any, were executed against data.

## Keeping the project log useful

After each meaningful work session or deliverable change, add one entry to [PROJECT_LOG.md](PROJECT_LOG.md) with the date, actual contributors, what changed, why it matters, evidence, review/test outcome and the next action. Link a commit or pull request when available; an artifact path can be used for drafting work that is not yet committed.

Keep entries newest first and preserve earlier entries. Record corrections explicitly rather than silently rewriting the history. At each reporting checkpoint, complete a dated snapshot referencing the relevant entry IDs. The log is **manually maintained**; it does not automatically read GitHub activity. Git history supplies technical evidence, while the log explains the project outcome and decisions.

## Submission and LLM disclosure

Before submission, verify the two dataset profiles; review the model and five queries; agree contribution percentages; and complete the report's shared-chat links. Export `Report.pdf` and recheck the three-page limit after final edits. A longer repository log does not replace the required short report.

ChatGPT assisted with scope refinement, metric and model proposals, draft SQL, the data dictionary, report editing, and this README/log. The group is responsible for reviewing the outputs and checking them against the sources. Record all AI/LLM conversations used, not only the latest one, in the [disclosure register](PROJECT_LOG.md#llm-disclosure-register), and include accessible links in the final report.

**Project basis:** the team-supplied `part1_submission.docx`, the report-v1 DOCX and its companion files, and the team's project discussion dated 2026-10-05. External source links above identify the planned data sources; they do not certify that extracts have been obtained or validated.
