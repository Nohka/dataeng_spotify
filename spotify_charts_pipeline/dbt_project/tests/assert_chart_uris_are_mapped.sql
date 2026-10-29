{{ config(severity = 'warn') }}

-- Warns if many chart URIs have no entry in int_song_uri_map (e.g. the source dropped old URIs
-- from all_uris, which would split a song's history). Discovery baseline: 43 unmapped URIs.

SELECT
    COUNT(DISTINCT d.track_uri)     AS unmapped_uris
FROM {{ ref('stg_charts_songs_daily') }} d
    LEFT JOIN {{ ref('int_song_uri_map') }} m ON d.track_uri = m.track_uri
WHERE 0=0
    AND m.track_uri IS NULL
HAVING COUNT(DISTINCT d.track_uri) > 100
