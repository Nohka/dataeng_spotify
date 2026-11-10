-- A "Top-10 song" is a song with at least one Top-10 day in a week (days_top10 > 0).
-- "Last quarter" = the most recent COMPLETED calendar quarter, resolved via dim_date.

-- a week is attributed wholly to the quarter containing its ISO-week MONDAY,
-- so a week straddling the quarter boundary lands in the earlier quarter.

WITH last_quarter AS (
    SELECT
        (DATE_TRUNC('quarter', CURRENT_DATE) - INTERVAL '3 months')::date AS q_start
        , (DATE_TRUNC('quarter', CURRENT_DATE) - INTERVAL '1 day')::date  AS q_end
)

, top10_placements AS (
    SELECT DISTINCT
        l.label_group
        , f.track_uri
        , f.country_code
    FROM fact_song_weekly f
    JOIN dim_date  d ON d.date_key        = f.week_date_key
    JOIN dim_label l ON l.label_name_norm = f.label_name_norm
    CROSS JOIN last_quarter q
    WHERE f.days_top10 > 0
      AND f.country_code <> 'global' -- not a country
      AND l.label_name_norm <> '(unknown)' -- can't attribute streams
      AND d.week_start_date BETWEEN q.q_start AND q.q_end
)

SELECT
    (SELECT q_start FROM last_quarter)            AS quarter_start
    , (SELECT q_end FROM last_quarter)            AS quarter_end
    , label_group
    , COUNT(*)                                    AS top10_song_country_placements
    , COUNT(DISTINCT track_uri)                   AS top10_songs
    , COUNT(DISTINCT country_code)                AS countries
FROM top10_placements
GROUP BY label_group
ORDER BY
    top10_song_country_placements DESC
    , countries DESC
LIMIT 10;
