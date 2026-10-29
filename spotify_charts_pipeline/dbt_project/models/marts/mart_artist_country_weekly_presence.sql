-- Gold layer: Q1 - artist chart presence per country.
-- All logic lives in int_artist_country_weekly_presence; this model only exposes it to reporting.

SELECT
    *
FROM {{ ref('int_artist_country_weekly_presence') }}
