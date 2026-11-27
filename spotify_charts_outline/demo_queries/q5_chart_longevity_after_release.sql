WITH bounds AS (
    -- the chart history actually loaded
    SELECT
        MIN(d.week_start_date) AS first_week
        , MAX(d.week_start_date) AS last_week
    FROM fact_song_weekly f
    JOIN dim_date d ON d.date_key = f.week_date_key
)

, cohort AS (
    -- Songs released inside the loaded window AND early enough that all 13 weeks of
    -- their post-release life are observable.
    SELECT
        s.track_uri
        , s.release_date
    FROM dim_song s
    CROSS JOIN bounds b
    WHERE s.release_date IS NOT NULL
      AND s.release_date >= b.first_week
      AND s.release_date <= b.last_week - INTERVAL '13 weeks'
)

, per_song_country AS (
    SELECT
        f.country_code
        , f.track_uri
        -- distinct chart weeks inside the first 13 weeks after release
        , COUNT(DISTINCT f.week_date_key)                          AS weeks_on_chart_13
        , MIN(f.weeks_since_release)                               AS weeks_to_first_chart
        -- weeks_since_release at the week the song hit its best rank
        , (ARRAY_AGG(f.weeks_since_release ORDER BY f.best_rank ASC, f.weeks_since_release ASC))[1]
                                                                   AS weeks_to_peak
        , MIN(f.best_rank)                                         AS best_rank
    FROM fact_song_weekly f
    JOIN cohort c ON c.track_uri = f.track_uri
    WHERE f.country_code <> 'global'
      AND f.weeks_since_release BETWEEN 0 AND 12 -- the fixed 13-week window
    GROUP BY
        f.country_code
        , f.track_uri
)

SELECT
    country_code
    , COUNT(*)                                                                 AS songs
    , ROUND(AVG(weeks_on_chart_13), 2)                                         AS avg_weeks_on_chart
    , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY weeks_on_chart_13)           AS median_weeks_on_chart
    , ROUND(AVG(weeks_to_first_chart), 2)                                      AS avg_weeks_release_to_first_chart
    , ROUND(AVG(weeks_to_peak), 2)                                             AS avg_weeks_release_to_peak
    , ROUND(AVG(best_rank), 1)                                                 AS avg_best_rank
FROM per_song_country
GROUP BY country_code
HAVING COUNT(*) >= 50  -- too few songs to compare otherwise
ORDER BY avg_weeks_on_chart DESC
LIMIT 15;
