-- Five questions from the three-page report. Run after schema and metric views.
-- PostgreSQL design SQL: no source data or query results are claimed.
SET search_path TO music_report_v1, public;

-- Q1: Hottest track(s) in Estonia in its latest complete week.
-- Preserve ties in Hotness. Report the actual week rather than saying "live".
WITH latest AS (
  SELECT MAX(c.iso_week_start_date) AS week_start
  FROM v_complete_market_week AS c
  JOIN dim_market AS m USING (market_key)
  WHERE m.market_code = 'EE'
), ranked AS (
  SELECT s.*,
         DENSE_RANK() OVER (ORDER BY s.weekly_hotness DESC) AS hotness_rank
  FROM v_track_weekly_summary AS s
  JOIN latest AS l ON l.week_start = s.iso_week_start_date
  WHERE s.market_code = 'EE'
)
SELECT iso_week_start_date, track_key, track_name, weekly_hotness,
       weekly_momentum, chart_days, observed_chart_streams
FROM ranked WHERE hotness_rank = 1
ORDER BY track_name, track_key;

-- Q2: Hottest reviewed local track(s) in the SAME latest complete EE week.
-- Unknown locality is excluded, not called "foreign" or "not local".
WITH latest AS (
  SELECT MAX(c.iso_week_start_date) AS week_start
  FROM v_complete_market_week AS c
  JOIN dim_market AS m USING (market_key)
  WHERE m.market_code = 'EE'
), ranked AS (
  SELECT s.*,
         DENSE_RANK() OVER (ORDER BY s.weekly_hotness DESC) AS hotness_rank
  FROM v_track_weekly_summary AS s
  JOIN latest AS l ON l.week_start = s.iso_week_start_date
  WHERE s.market_code = 'EE' AND s.locality_status = 'local'
)
SELECT iso_week_start_date, track_key, track_name,
       weekly_hotness, weekly_momentum
FROM ranked WHERE hotness_rank = 1
ORDER BY track_name, track_key;

-- Q3: Current labels' Top-20 Consistency across the fixed European panel.
-- Each label/market/week contributes at most once; denominator is shared.
WITH labels AS (
  SELECT DISTINCT record_label_current AS label
  FROM dim_track WHERE record_label_current IS NOT NULL
), hits AS (
  SELECT DISTINCT t.record_label_current AS label,
         f.market_key, d.iso_week_start_date
  FROM fact_track_chart_daily AS f
  JOIN dim_date AS d USING (date_key)
  JOIN dim_market AS m USING (market_key)
  JOIN dim_track AS t USING (track_key)
  JOIN v_europe_window_weeks AS w USING (iso_week_start_date)
  WHERE m.is_europe = TRUE AND m.market_code <> 'GLOBAL'
    AND f.chart_rank <= 20 AND t.record_label_current IS NOT NULL
), totals AS (
  SELECT label, COUNT(*) AS qualifying_market_weeks FROM hits GROUP BY label
), coverage AS (
  SELECT COUNT(*) AS common_complete_weeks,
         MIN(iso_week_start_date) AS first_observed_week,
         MAX(iso_week_start_date) AS window_end_week
  FROM v_europe_window_weeks
), panel AS (
  SELECT COUNT(*) AS market_count FROM dim_market
  WHERE is_europe = TRUE AND market_code <> 'GLOBAL'
)
SELECT l.label,
       COALESCE(t.qualifying_market_weeks, 0) AS qualifying_market_weeks,
       c.common_complete_weeks, p.market_count, c.window_end_week,
       100.0 * COALESCE(t.qualifying_market_weeks, 0)
          / NULLIF(c.common_complete_weeks * p.market_count, 0)
          AS top20_consistency_pct
FROM labels AS l
LEFT JOIN totals AS t USING (label)
CROSS JOIN coverage AS c CROSS JOIN panel AS p
WHERE c.common_complete_weeks > 0 AND p.market_count > 0
ORDER BY top20_consistency_pct DESC, l.label;

-- Q4: Artists' Top-20 Consistency within Estonia's fixed 12-week window.
-- A collaboration counts as presence for every credited artist, but a given
-- artist receives at most one qualifying observation per market/week.
WITH hits AS (
  SELECT DISTINCT b.artist_key, d.iso_week_start_date
  FROM fact_track_chart_daily AS f
  JOIN dim_date AS d USING (date_key)
  JOIN dim_market AS m USING (market_key)
  JOIN bridge_track_artist AS b USING (track_key)
  JOIN v_estonia_window_weeks AS w USING (iso_week_start_date)
  WHERE m.market_code = 'EE' AND f.chart_rank <= 20
), totals AS (
  SELECT artist_key, COUNT(*) AS qualifying_weeks FROM hits GROUP BY artist_key
), coverage AS (
  SELECT COUNT(*) AS complete_weeks,
         MAX(iso_week_start_date) AS window_end_week
  FROM v_estonia_window_weeks
)
SELECT a.artist_key, a.artist_name, c.window_end_week,
       COALESCE(t.qualifying_weeks, 0) AS qualifying_weeks,
       c.complete_weeks,
       100.0 * COALESCE(t.qualifying_weeks, 0) / NULLIF(c.complete_weeks, 0)
          AS top20_consistency_pct
FROM dim_artist AS a
LEFT JOIN totals AS t USING (artist_key)
CROSS JOIN coverage AS c
WHERE c.complete_weeks > 0
ORDER BY top20_consistency_pct DESC, a.artist_name, a.artist_key;

-- Q5: Where does a selected artist have the most distinct chart-presence days?
-- Replace NULL below with a quoted REAL Spotify artist URI from dim_artist.
-- NULL is intentional: no artist identifier or result is invented.
-- All countries use the same common complete weeks. This is NOT listener count.
WITH params AS (
  SELECT CAST(NULL AS TEXT) AS spotify_artist_uri
), selected_artist AS (
  SELECT a.artist_key, a.artist_name
  FROM dim_artist AS a JOIN params AS p USING (spotify_artist_uri)
), artist_days AS (
  SELECT DISTINCT a.artist_key, f.market_key, f.date_key
  FROM selected_artist AS a
  JOIN bridge_track_artist AS b USING (artist_key)
  JOIN fact_track_chart_daily AS f USING (track_key)
  JOIN dim_date AS d USING (date_key)
  JOIN v_europe_window_weeks AS w USING (iso_week_start_date)
), coverage AS (
  SELECT COUNT(*) AS common_complete_weeks,
         MAX(iso_week_start_date) AS window_end_week
  FROM v_europe_window_weeks
)
SELECT a.artist_name, m.market_code, m.market_name,
       COUNT(ad.date_key) AS chart_presence_days,
       7 * c.common_complete_weeks AS eligible_days,
       c.common_complete_weeks, c.window_end_week
FROM selected_artist AS a
CROSS JOIN dim_market AS m CROSS JOIN coverage AS c
LEFT JOIN artist_days AS ad
  ON ad.artist_key = a.artist_key AND ad.market_key = m.market_key
WHERE m.is_europe = TRUE AND m.market_code <> 'GLOBAL'
  AND c.common_complete_weeks > 0
GROUP BY a.artist_name, a.artist_key, m.market_key, m.market_code, m.market_name,
         c.common_complete_weeks, c.window_end_week
ORDER BY chart_presence_days DESC, m.market_code;
