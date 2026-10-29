-- Gold layer: artist dimension. All logic lives in int_artist.

SELECT
    *
FROM {{ ref('int_artist') }}
