-- Gold layer: song dimension. All logic lives in int_song.

SELECT
    *
FROM {{ ref('int_song') }}
