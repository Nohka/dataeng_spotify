-- Run after 01_core_schema.sql. These views return no fabricated data.
-- Proposed PostgreSQL SQL; validate against the actual extract and server.
BEGIN;
SET search_path TO music_report_v1, public;

-- A complete week needs all seven calendar dates marked complete.
-- The date dimension check constrains each date to its actual Monday boundary.
CREATE OR REPLACE VIEW v_complete_market_week AS
SELECT o.market_key, d.iso_week_start_date
FROM ops_chart_load_daily AS o
JOIN dim_date AS d USING (date_key)
GROUP BY o.market_key, d.iso_week_start_date
HAVING COUNT(*) = 7
   AND SUM(CASE WHEN o.load_status = 'complete' THEN 1 ELSE 0 END) = 7;

CREATE OR REPLACE VIEW v_track_weekly AS
SELECT f.market_key, f.track_key, d.iso_week_start_date,
       COUNT(*) AS chart_days,
       MIN(f.chart_rank) AS best_rank,
       100.0 / 7.0 * SUM((201.0 - f.chart_rank) / 200.0) AS weekly_hotness,
       CASE WHEN COUNT(f.streams) = COUNT(*) THEN SUM(f.streams) END
           AS observed_chart_streams
FROM fact_track_chart_daily AS f
JOIN dim_date AS d USING (date_key)
JOIN v_complete_market_week AS c
  ON c.market_key = f.market_key
 AND c.iso_week_start_date = d.iso_week_start_date
GROUP BY f.market_key, f.track_key, d.iso_week_start_date;

-- Missing prior track rows imply zero visibility ONLY if the prior calendar
-- week is complete. This view includes tracks present in the current week;
-- an all-exits report would require a separate full outer join between weeks.
CREATE OR REPLACE VIEW v_track_weekly_summary AS
SELECT w.*, m.market_code, t.track_name, t.record_label_current,
       CASE WHEN pc.market_key IS NOT NULL
            THEN w.weekly_hotness - COALESCE(p.weekly_hotness, 0.0)
       END AS weekly_momentum,
       CASE
         WHEN EXISTS (
           SELECT 1
           FROM bridge_track_artist AS b
           JOIN artist_locality AS l ON l.artist_key = b.artist_key
           WHERE b.track_key = w.track_key
             AND l.market_key = w.market_key
             AND l.rule_version = 'v1' AND l.local_status = 'local'
         ) THEN 'local'
         WHEN EXISTS (
           SELECT 1 FROM bridge_track_artist AS b
           WHERE b.track_key = w.track_key
         ) AND NOT EXISTS (
           SELECT 1 FROM bridge_track_artist AS b
           LEFT JOIN artist_locality AS l
             ON l.artist_key = b.artist_key AND l.market_key = w.market_key
            AND l.rule_version = 'v1'
           WHERE b.track_key = w.track_key
             AND l.local_status IS DISTINCT FROM 'not_local'
         ) THEN 'not_local'
         ELSE 'unknown'
       END AS locality_status
FROM v_track_weekly AS w
JOIN dim_market AS m USING (market_key)
JOIN dim_track AS t USING (track_key)
LEFT JOIN v_complete_market_week AS pc
  ON pc.market_key = w.market_key
 AND pc.iso_week_start_date = w.iso_week_start_date - 7
LEFT JOIN v_track_weekly AS p
  ON p.market_key = w.market_key AND p.track_key = w.track_key
 AND p.iso_week_start_date = w.iso_week_start_date - 7;

-- The entire documented panel must be present in dim_market. Do not silently
-- remove a country from the panel merely because its source chart is missing.
CREATE OR REPLACE VIEW v_common_europe_week AS
SELECT c.iso_week_start_date
FROM v_complete_market_week AS c
JOIN dim_market AS m USING (market_key)
WHERE m.is_europe = TRUE AND m.market_code <> 'GLOBAL'
GROUP BY c.iso_week_start_date
HAVING COUNT(*) = (
  SELECT COUNT(*) FROM dim_market
  WHERE is_europe = TRUE AND market_code <> 'GLOBAL'
);

-- Fixed 12-calendar-week window ending at the latest comparable week.
-- Gaps are excluded, not silently replaced by older weeks. Queries show coverage.
CREATE OR REPLACE VIEW v_europe_window_weeks AS
SELECT c.iso_week_start_date
FROM v_common_europe_week AS c
WHERE c.iso_week_start_date BETWEEN
      (SELECT MAX(iso_week_start_date) - 77 FROM v_common_europe_week)
  AND (SELECT MAX(iso_week_start_date) FROM v_common_europe_week);

CREATE OR REPLACE VIEW v_estonia_window_weeks AS
WITH estonia_weeks AS (
  SELECT c.iso_week_start_date
  FROM v_complete_market_week AS c
  JOIN dim_market AS m USING (market_key)
  WHERE m.market_code = 'EE'
)
SELECT iso_week_start_date FROM estonia_weeks
WHERE iso_week_start_date BETWEEN
      (SELECT MAX(iso_week_start_date) - 77 FROM estonia_weeks)
  AND (SELECT MAX(iso_week_start_date) FROM estonia_weeks);
COMMIT;
