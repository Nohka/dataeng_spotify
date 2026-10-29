-- Staging: one row per song. Only renames and data types.

SELECT
    track_uri -- the song's main URI, used as song_id downstream
    , track_name
    , artist_names  -- '|'-separated
    , artist_uris -- '|'-separated
    , NULLIF(TRIM(label), '')  AS label -- normalise names and also assign explicit NULL if name missing
    , TRY_CAST(release_date AS DATE)  AS release_date
    , all_uris   -- '|'-separated list of every URI of this song
FROM {{ source('spotify', 'songs') }}
