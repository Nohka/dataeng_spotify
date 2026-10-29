-- Gold layer: Q2 hottest song this week, Q3 labels with hits, Q4 breakouts.
-- All logic lives in int_songs_weekly; this model only exposes it to reporting.

SELECT
    *
FROM {{ ref('int_songs_weekly') }}
