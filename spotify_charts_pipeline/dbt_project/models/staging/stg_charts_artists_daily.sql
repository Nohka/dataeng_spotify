-- Staging: one row per source row. Only renames and data types, no business logic.
-- The only filter is the analysis window (var start_date), so downstream models only read data from start_date onwards.

SELECT
    CAST(date AS DATE)                              AS chart_date
    , LOWER(country)                                AS country_code      -- 'global' = worldwide chart
    , CAST(rank AS INTEGER)                         AS chart_rank
    , uri                                           AS artist_uri
    , artist_name
    , CAST(peak_rank AS INTEGER)                    AS peak_rank
    , NULLIF(CAST(previous_rank AS INTEGER), -1)    AS previous_rank     -- source uses -1 for "not on chart yesterday"
    , CAST(days_on_chart AS INTEGER)                AS days_on_chart
    , CAST(consecutive_days AS INTEGER)             AS consecutive_days
    , entry_status
    , CAST(peak_date AS DATE)                       AS peak_date
    , CAST(entry_rank AS INTEGER)                   AS entry_rank
    , CAST(entry_date AS DATE)                      AS entry_date
FROM {{ source('spotify', 'charts_artists_daily') }}
WHERE 0=0
    AND CAST(date AS DATE) >= DATE '{{ var("start_date") }}'
