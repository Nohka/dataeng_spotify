-- "Presence" = presence_score = rank_points / 200 summed over the window, where
-- rank_points = SUM(201 - daily rank).
-- 'global' is excluded: it is not a country and its rows overlap the per-country ones.

WITH params AS (
    SELECT 'Bad Bunny'::varchar AS artist_name  -- <= this is changed to the atrist of interest
)

, chosen_artists AS (
    SELECT
        a.artist_uri
        , a.artist_name
    FROM dim_artist a, params p
    WHERE a.artist_name = p.artist_name
)

, per_country AS (
    SELECT
        a.artist_name
        , a.artist_uri
        , f.country_code
        , SUM(f.days_on_chart)                                       AS days_on_chart
        , SUM(f.days_top20)                                          AS days_top20
        , MIN(f.best_rank)                                           AS best_rank
        -- day-weighted mean rank: sum of ranks / number of charted days
        , ROUND(SUM(f.rank_sum)::numeric / SUM(f.days_on_chart), 2)   AS avg_rank
        , SUM(f.rank_points)                                         AS rank_points
        , ROUND(SUM(f.presence_score), 4)                            AS presence_score
    FROM fact_artist_weekly f
        JOIN chosen_artists a 
            ON a.artist_uri = f.artist_uri
        JOIN dim_date d 
            ON d.date_key   = f.week_date_key
    WHERE 0=0
        AND f.country_code <> 'global'
        AND d.full_date >= CURRENT_DATE - INTERVAL '52 weeks'
    GROUP BY
        a.artist_name
        , a.artist_uri
        , f.country_code
)

SELECT
    DENSE_RANK() OVER (PARTITION BY artist_uri ORDER BY rank_points DESC) AS presence_rank
    , artist_name
    , country_code
    , days_on_chart
    , days_top20
    , best_rank
    , avg_rank
    , rank_points
    , presence_score
FROM per_country
ORDER BY
    presence_rank
    , country_code
LIMIT 10;
