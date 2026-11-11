-- Q5: How long does a song typically stay on the chart after release, and does it differ by country?
-- Songs released in the window whose chart run has ended. Medians, because a few long hits pull the average up.
-- Runs on the DuckDB warehouse (with the raw Postgres database attached as 'raw').

SELECT
    c.country_name
    , COUNT(*)                                  AS songs
    , MEDIAN(l.chart_days)                      AS median_chart_days
    , MEDIAN(l.days_release_to_exit)            AS median_days_release_to_exit
    , MEDIAN(l.days_release_to_entry)           AS median_days_release_to_entry
    , ROUND(AVG(l.chart_days), 1)               AS avg_chart_days
FROM mart_song_chart_lifespan l
    INNER JOIN dim_country c USING (country_code)
WHERE 0=0
    AND NOT l.is_still_charting
GROUP BY c.country_name
ORDER BY median_chart_days DESC
