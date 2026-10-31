-- Q4: Which songs are breaking out?
-- Largest week-over-week stream gain among songs outside the Top 20 last week (or not on the chart),
-- in the latest week where this and last week are complete.
-- Runs on the DuckDB warehouse (with the raw Postgres database attached as 'raw').

SELECT
    w.week_start
    , w.country_code
    , s.track_name
    , s.artist_names
    , w.prev_week_best_rank
    , w.best_rank
    , w.prev_week_streams
    , w.weekly_streams
    , w.stream_gain_wow
FROM mart_songs_weekly w
    INNER JOIN dim_song s USING (song_id)
WHERE 0=0
    AND w.country_code <> 'global'
    AND w.is_complete_week
    AND w.is_prev_week_complete
    AND w.was_outside_top_n_prev_week
QUALIFY w.week_start = MAX(w.week_start) OVER ()
ORDER BY w.stream_gain_wow DESC
LIMIT 10
