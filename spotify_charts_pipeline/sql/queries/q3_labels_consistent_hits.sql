-- Q3: Which record labels are consistently producing hits?
-- Hit = a song's first week in the Top 10 of any chart; counted in the month of that week's Monday.
-- Consistency = share of months with at least one new hit.
-- Runs on the DuckDB warehouse (with the raw Postgres database attached as 'raw').

WITH first_hit AS (
    -- each hit song once: the first week it reached the Top 10 in any chart
    SELECT
        w.song_id
        , LOWER(w.label)                                        AS label_key
        , w.label
        , CAST(DATE_TRUNC('month', w.week_start) AS DATE)       AS hit_month   -- month of the week's Monday
    FROM mart_songs_weekly w
    WHERE 0=0
        AND w.best_rank <= 10
        AND w.label IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY w.song_id
        ORDER BY
            w.week_start
            , w.best_rank
    ) = 1
)

, period AS (
    -- number of months in the data
    SELECT
        COUNT(DISTINCT DATE_TRUNC('month', w.week_start))       AS months_in_period
    FROM mart_songs_weekly w
)

SELECT
    MODE(f.label)                                               AS label_name   -- most common spelling
    , COUNT(*)                                                  AS hit_songs
    , COUNT(DISTINCT f.hit_month)                               AS months_with_new_hit
    , p.months_in_period
    , ROUND(100.0 * COUNT(DISTINCT f.hit_month) / p.months_in_period, 1)
                                                                AS pct_months_with_new_hit
FROM first_hit f
    CROSS JOIN period p
GROUP BY
    f.label_key
    , p.months_in_period
ORDER BY
    months_with_new_hit DESC
    , hit_songs DESC
LIMIT 10
