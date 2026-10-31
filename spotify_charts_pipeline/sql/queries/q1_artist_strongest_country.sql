-- Q1: For a given artist, in which country is their chart presence the strongest?
-- Weekly points are summed over the whole period, then the countries are ranked. Artists are grouped
-- by artist_uri, so two artists with the same name stay separate. Change the artist name below.
-- Runs on the DuckDB warehouse (with the raw Postgres database attached as 'raw').

SELECT
    a.artist_name
    , p.artist_uri
    , p.country_code
    , SUM(p.chart_days)                                         AS chart_days
    , MIN(p.best_rank)                                          AS best_rank
    , ROUND(SUM(p.rank_sum) / SUM(p.chart_days), 1)             AS avg_rank     -- day-weighted, not an average of weekly averages
    , SUM(p.presence_points)                                    AS presence_points
    , RANK() OVER (
        PARTITION BY p.artist_uri
        ORDER BY SUM(p.presence_points) DESC
    )                                                           AS country_rank_for_artist
FROM mart_artist_country_weekly_presence p
    INNER JOIN dim_artist a USING (artist_uri)
WHERE 0=0
    AND a.artist_name = 'Taylor Swift'
GROUP BY
    a.artist_name
    , p.artist_uri
    , p.country_code
QUALIFY country_rank_for_artist <= 5
ORDER BY
    p.artist_uri
    , country_rank_for_artist
