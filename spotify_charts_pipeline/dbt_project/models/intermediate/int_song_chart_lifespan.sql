-- Q5: how long a song stays on the chart after release. One row per song_id x country.
-- Release date: the source release_date is the album the track is linked to NOW, which is often
-- later than the real first release (discovery: Halsey "Without Me" shows 2020-01-17).
-- So release = the earliest of release_date and the song's first chart entry (entry_date) anywhere.
-- Only songs released on/after start_date are kept: their whole chart life is inside our data.
-- is_still_charting = TRUE means the run is not finished yet (exclude these for "typical" lengths).

WITH song_release AS ( --finds each song’s release date
    SELECT
        d.song_id
        , LEAST(MIN(d.release_date), MIN(d.entry_date))    AS release_date
        -- The source release_date isn’t reliable as a first release date. It’s the date of the album the track is linked to now, which is
        -- often later than the single. For Halsey’s “Without Me” it shows 2020-01-17, although the song was on the chart from 2018.
        -- So the model takes the earlier of two dates:
            --MIN(d.release_date): the earliest release date of any of the song’s URIs.
            --MIN(d.entry_date): the first day the song appeared on any country’s chart. entry_date comes from the source and goes back before your window, so it shows when the song first charted.
      -- A song can’t chart before it’s released, so if the first chart entry is earlier, that date is the better estimate. LEAST ignores NULLs, so a
      --song without a release_date still gets its first entry_date.
    FROM {{ ref('int_charts_songs_daily') }} d
    GROUP BY d.song_id
)

, runs AS (
    -- the song's chart life in each country
    SELECT
        d.song_id
        , d.country_code
        , ARG_MIN(d.track_name, d.chart_rank)               AS track_name
        , ARG_MIN(d.artist_names, d.chart_rank)             AS artist_names
        , MIN(d.chart_date)                                 AS first_chart_date
        , MAX(d.chart_date)                                 AS last_chart_date
        , COUNT(DISTINCT d.chart_date)                      AS chart_days      -- days actually on the chart (gaps excluded)
        , MIN(d.chart_rank)                                 AS best_rank
    FROM {{ ref('int_charts_songs_daily') }} d
    GROUP BY ALL
)

, last_data_day AS (
    -- latest chart date per country, to spot runs that are still going
    SELECT
        d.country_code
        , MAX(d.chart_date)                                 AS last_data_date
    FROM {{ ref('int_charts_songs_daily') }} d
    GROUP BY ALL
)

SELECT
    r.song_id
    , r.country_code
    , r.track_name
    , r.artist_names
    , s.release_date
    , r.first_chart_date
    , r.last_chart_date
    , r.chart_days
    , r.best_rank
    , r.first_chart_date - s.release_date                   AS days_release_to_entry   -- DATE - DATE = days
    , r.last_chart_date - s.release_date + 1                AS days_release_to_exit    -- release day counts as day 1
    , r.last_chart_date = l.last_data_date                  AS is_still_charting
FROM runs r
    INNER JOIN song_release s USING (song_id)
    INNER JOIN last_data_day l USING (country_code)
WHERE 0=0
    AND s.release_date >= DATE '{{ var("start_date") }}' -- NOTE: metrics only cover songs released in the window
