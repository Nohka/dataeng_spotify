-- "Hot" = heat_score = weekly_streams x (1 + week-over-week growth restricted to
-- [-0.5, +1.0]).

-- Row 1 is the answer; the rest is context showing the metric behaving.

WITH latest_complete_week AS (
    SELECT MAX(week_date_key) AS week_date_key
    FROM fact_song_weekly
    WHERE 0=0
        AND country_code = 'ee'
        AND days_on_chart = 7 -- the week is finished
)

SELECT
    d.week_start_date
    , d.week_end_date
    , s.track_name
    , s.primary_artist_name
    , f.best_rank
    , f.weekly_streams
    , f.days_on_chart
    , f.days_with_streams
    , ROUND(f.stream_growth_wow * 100, 1) AS growth_vs_last_week_pct
    , f.heat_score
FROM fact_song_weekly f
    JOIN latest_complete_week w 
        ON w.week_date_key = f.week_date_key
    JOIN dim_song s 
        ON s.track_uri = f.track_uri
    JOIN dim_date d 
        ON d.date_key  = f.week_date_key
WHERE f.country_code = 'ee'
ORDER BY f.heat_score DESC
LIMIT 10;
