-- Gold layer: Q5 - chart life after release per country.
-- All logic lives in int_song_chart_lifespan; this model only exposes it to reporting.

SELECT
    *
FROM {{ ref('int_song_chart_lifespan') }}
