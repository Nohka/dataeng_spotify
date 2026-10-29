-- Artist dimension logic. One row per artist_uri.
-- Artists come from artists.csv. Chart artists missing from artists.csv are added as "unknown"
-- artists with their latest chart spelling, so every artist_uri in the facts has a dimension row.
-- Listener numbers from artists.csv are left out: they are a snapshot of one day and change
-- daily, so they are measures, not artist attributes.
-- Note: artist_name is not unique (same-name profiles exist, e.g. two Luis Gabriels).

WITH known_artists AS (
    SELECT
        a.artist_uri
        , a.artist_name
        , FALSE                                     AS is_unknown_artist
    FROM {{ ref('stg_artists') }} a
)

, unknown_artists AS (
    -- artist_uris on the chart that are not in artists.csv
    SELECT
        c.artist_uri
        , ARG_MAX(c.artist_name, c.chart_date)      AS artist_name     -- latest spelling on the chart
        , TRUE                                      AS is_unknown_artist
    FROM {{ ref('int_charts_artists_daily') }} c
    WHERE 0=0
        AND NOT EXISTS (
            SELECT 1
            FROM {{ ref('stg_artists') }} a
            WHERE a.artist_uri = c.artist_uri
        )
    GROUP BY c.artist_uri
)

SELECT * FROM known_artists
UNION ALL
SELECT * FROM unknown_artists
