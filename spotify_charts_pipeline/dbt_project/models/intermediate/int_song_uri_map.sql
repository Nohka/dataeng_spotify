-- One row per Spotify track URI -> the song it belongs to (song_id).
-- Spotify gives one song several URIs (e.g. single vs album release). songs.all_uris lists them all,
-- and the chart switches between them (discovery: "Distance" charted under 2 URIs).
-- Discovery: every URI belongs to exactly one song. This is enforced by the unique test on track_uri,
-- which fails the build if a URI is ever listed under two songs.

-- Must stay a view (or a fully rebuilt table), never incremental: if the source changes a song's main
-- URI, all chart rows have to be re-mapped to the new song_id.

-- Map every URI of a song to its main URI. One row per URI in all_uris.
SELECT
    UNNEST(STRING_SPLIT(COALESCE(s.all_uris, s.track_uri), '|'))   AS track_uri
    , s.track_uri                                                   AS song_id      -- the main URI
FROM {{ ref('stg_songs') }} s
