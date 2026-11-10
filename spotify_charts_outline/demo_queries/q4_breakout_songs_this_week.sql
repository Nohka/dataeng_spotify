WITH latest_complete_week AS (
    SELECT MAX(week_date_key) AS week_date_key
    FROM fact_song_weekly
    WHERE 0=0
      AND country_code = 'ee'
      AND days_on_chart = 7
)

SELECT
    d.week_start_date
    , d.week_end_date
    , s.track_name
    , s.primary_artist_name
    , CASE WHEN f.charted_prev_week
           THEN f.prev_week_best_rank::text
           ELSE 'not on chart' END            AS position_last_week
    , f.best_rank                             AS best_rank_this_week
    , f.prev_week_streams
    , f.weekly_streams
    , f.stream_gain_wow
    , ROUND(f.stream_growth_wow * 100, 1)     AS growth_pct
FROM fact_song_weekly f
  JOIN latest_complete_week w 
    ON w.week_date_key = f.week_date_key
  JOIN dim_song s 
    ON s.track_uri = f.track_uri
  JOIN dim_date d 
    ON d.date_key  = f.week_date_key
WHERE 0=0
  AND f.country_code = 'ee'
  -- not in the Top 20 last week -> either absent from the chart, or ranked below 20
  AND (NOT f.charted_prev_week OR f.prev_week_best_rank > 20)
  AND f.weekly_streams >= 5000  -- filter out noisy tracks
ORDER BY f.stream_gain_wow DESC NULLS LAST
LIMIT 10;
