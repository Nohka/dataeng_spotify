-- Song dimension logic. One row per song_id.
-- Songs come from songs.csv: one row per song, song_id = the song's main URI.
-- Chart URIs missing from songs.csv (discovery: 43 URIs, no name or label) keep their own URI
-- as song_id in int_charts_songs_daily. They are added here as "unknown" songs, so every
-- song_id in the facts has a matching dimension row.
-- Both CTEs must list the same columns in the same order (UNION ALL matches by position).

WITH known_songs AS (
    SELECT
        s.track_uri                                                     AS song_id
        , s.track_name
        , s.artist_names
        , s.artist_uris
        , s.label
        , s.release_date                                                -- source date: the album the track is linked to now
        , LEN(STRING_SPLIT(COALESCE(s.all_uris, s.track_uri), '|'))    AS uri_count
        , FALSE                                                         AS is_unknown_song
    FROM {{ ref('stg_songs') }} s
)

, unknown_songs AS (
    -- song_ids on the chart that are not in songs.csv
    SELECT
        d.song_id
        , ARG_MIN(d.track_name, d.chart_rank)                           AS track_name      -- usually NULL
        , ARG_MIN(d.artist_names, d.chart_rank)                         AS artist_names    -- usually NULL
        , CAST(NULL AS VARCHAR)                                         AS artist_uris
        , ARG_MIN(d.label, d.chart_rank)                                AS label
        , MIN(d.release_date)                                           AS release_date
        , 1                                                             AS uri_count
        , TRUE                                                          AS is_unknown_song
    FROM {{ ref('int_charts_songs_daily') }} d
    WHERE 0=0
        AND NOT EXISTS (
            SELECT 1
            FROM {{ ref('stg_songs') }} s
            WHERE s.track_uri = d.song_id
        )
    GROUP BY d.song_id
)

SELECT * FROM known_songs
UNION ALL
SELECT * FROM unknown_songs
