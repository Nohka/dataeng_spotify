-- Weekly song chart per country. One row per week_start x country x song_id.
-- Used by Q2 (hottest song this week), Q3 (labels with hits) and Q4 (breakouts).
-- Different URIs of one song are combined here: streams are summed (they are separate real
-- chart entries), rank = the best position of any of its URIs.
-- Streams are only known for days in the Top 200, so a song's weekly streams = its charted streams.

WITH params AS (
    -- Q4 breakout threshold: a song is a breakout candidate if it was outside this Top N last week
    SELECT
        20                                          AS breakout_top_n
)

, weekly AS (
    -- Weekly metrics per song x country, from the daily chart rows.
    -- int_charts_songs_daily has one row per chart_date x country x track_uri, not per song_id:
    -- two URIs of the same song on the same day are both kept (real separate chart entries).
    -- A song can therefore have several rows per day and per week, with different track_uri
    -- and sometimes slightly different names (same day, or after a URI switch during the week).
    -- Here everything is combined to one row per song_id:
    --   - track_name, artist_names: taken from the best-ranked row of the week
    --   - weekly_streams: sum over all days and all URIs of the song
    --   - best_rank: best rank (lowest number) of any URI on any day of the week
    --   - days_on_chart: distinct days, so a day with two URIs counts once
    --   - label: taken from the best-ranked row of the week that has a label
    SELECT
        d.week_start
        , d.country_code
        , d.song_id
        , ARG_MIN(d.track_name, d.chart_rank)       AS track_name        -- name from the best-ranked row
        , ARG_MIN(d.artist_names, d.chart_rank)     AS artist_names
        , ARG_MIN(d.label, d.chart_rank) FILTER (WHERE d.label IS NOT NULL) AS label  -- label from the best-ranked row that has one
        , SUM(d.streams)                            AS weekly_streams
        , MIN(d.chart_rank)                         AS best_rank
        , COUNT(DISTINCT d.chart_date)              AS days_on_chart
    FROM {{ ref('int_charts_songs_daily') }} d
    GROUP BY
        d.week_start
        , d.country_code
        , d.song_id
)

-- number of chart days each country has in a week: 7 = complete week.
-- The first week (data starts on a Wednesday) and the latest week are usually incomplete,
-- and the dataset has a few missing days.
, country_weeks AS (
    SELECT
        d.week_start
        , d.country_code
        , COUNT(DISTINCT d.chart_date)              AS chart_days_in_week
    FROM {{ ref('int_charts_songs_daily') }} d
    GROUP BY ALL
)

, country_weeks_prev AS (
    -- add the country's previous week, to know if it is complete too
    -- PURPOSE: adds the previous week’s values to each country’s week, so the model can check whether last week was complete.
    -- WHY NEEDED: That matters for Q4: if last week had only 4 chart days, last week’s streams look too low, and every song’s week-over-week gain looks too high.
    SELECT
        cw.*
      -- LAG(column) OVER (...) returns that column’s value from the previous row, according to the window’s order
        , LAG(cw.week_start) OVER country_order         AS prev_country_week
        , LAG(cw.chart_days_in_week) OVER country_order AS prev_chart_days_in_week
    FROM country_weeks cw
    WINDOW country_order AS (
        PARTITION BY cw.country_code -- each country is handled separately, so Estonia’s first week never looks at another country’s last week
        ORDER BY cw.week_start -- “previous row” means the previous week in time
    )
)

, with_prev AS (
    -- We have the Q4 WOW growth question, so adding the WOW growth as a metric in the model.
    -- For other period growths these logics can be defined when querying the gold layer itself.
    -- the song's previous charted week; LAG is cheaper than joining the weekly table to itself
    SELECT
        w.*
        , LAG(w.week_start) OVER song_weeks         AS prev_week_start
        , LAG(w.weekly_streams) OVER song_weeks     AS prev_weekly_streams
        , LAG(w.best_rank) OVER song_weeks          AS prev_best_rank
    FROM weekly w
    WINDOW song_weeks AS (
        PARTITION BY
            w.country_code
            , w.song_id
        ORDER BY w.week_start
    )
)

, final AS (
    SELECT
        p.week_start
        , p.country_code
        , p.song_id
        , p.track_name
        , p.artist_names
        , p.label
        , p.weekly_streams
        , p.best_rank
        , p.days_on_chart
        , cw.chart_days_in_week = 7                                                                     AS is_complete_week
        -- the country's previous week must exist, be exactly 7 days earlier and be complete
          -- prev_country_week = week_start - 7: the previous row really is last week.
          -- prev_chart_days_in_week = 7: that week has all 7 days.
        , COALESCE(cw.prev_country_week = p.week_start - 7 AND cw.prev_chart_days_in_week = 7, FALSE)   AS is_prev_week_complete
        -- previous week values only count if the song's previous chart week was exactly last week
        , CASE WHEN p.prev_week_start = p.week_start - 7 THEN p.prev_weekly_streams END                 AS prev_week_streams
        , CASE WHEN p.prev_week_start = p.week_start - 7 THEN p.prev_best_rank END                      AS prev_week_best_rank
    FROM with_prev p
        INNER JOIN country_weeks_prev cw
            ON  cw.country_code = p.country_code
            AND cw.week_start   = p.week_start
)

SELECT
    f.*
    , f.weekly_streams - COALESCE(f.prev_week_streams, 0)                                   AS stream_gain_wow   -- absolute gain, a new entry gains all its streams
    , ROUND(100.0 * (f.weekly_streams - f.prev_week_streams) / f.prev_week_streams, 1)      AS stream_growth_pct_wow
    , COALESCE(f.prev_week_best_rank, 999) > pr.breakout_top_n                              AS was_outside_top_n_prev_week  -- not charting also counts
    -- position of the song in this country & week by streams (1 = most streamed)
    , ROW_NUMBER() OVER (
        PARTITION BY
            f.country_code
            , f.week_start
        ORDER BY
            f.weekly_streams DESC
            , f.best_rank
    )                                                                                       AS streams_rank_in_week
FROM final f
  CROSS JOIN params pr        -- one row, so every row gets the same threshold
