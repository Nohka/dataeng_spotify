-- Q2: What is the hottest song in Estonia this week?
-- Hottest = most streams in the latest complete week (all 7 chart days available).
-- Runs on the DuckDB warehouse (with the raw Postgres database attached as 'raw').

SELECT
    w.week_start
    , w.streams_rank_in_week
    , s.track_name
    , s.artist_names
    , w.weekly_streams
    , w.best_rank
    , w.stream_growth_pct_wow
FROM mart_songs_weekly w
    INNER JOIN dim_song s USING (song_id)
WHERE 0=0
    AND w.country_code = 'ee'
    AND w.is_complete_week
-- keep only the latest complete week (one scan instead of a separate MAX query)
QUALIFY w.week_start = MAX(w.week_start) OVER ()
ORDER BY w.streams_rank_in_week
LIMIT 5
