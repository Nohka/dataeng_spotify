-- Discovery assumption behind the dedup in int_charts_songs_daily:
-- if the same URI appears twice on one chart day, both rows have the same streams.
-- Returns rows (= test fails) if a new data version breaks this.

SELECT
    s.chart_date
    , s.country_code
    , s.track_uri
FROM {{ ref('stg_charts_songs_daily') }} s
GROUP BY ALL
HAVING 0=0
    AND COUNT(*) > 1
    AND COUNT(DISTINCT s.streams) > 1
