-- Daily song chart rows (from start_date onwards), cleaned. One row per chart_date x country x track_uri.
-- Two fixes from discovery:
--   1) Duplicate records: the same URI twice on one chart day at different ranks, always with
--      identical streams (192 cases). They are one entry recorded twice -> keep the better rank.
--   2) song_id: different URIs of the same song get one song_id, so they can be combined later.
--      Those rows are NOT duplicates (different streams, own chart history) and are kept --> THESE ARE COMBINED LATER in int_songs_weekly
--      Examples: Re-release or remaster, Single and album version etc

WITH deduplicated AS (
    SELECT
        c.chart_date
        , c.country_code
        , c.chart_rank
        , c.track_uri
        , c.track_name
        , c.artist_names
        , c.artist_uris
        , c.label
        , c.streams
        , c.peak_rank
        , c.previous_rank
        , c.days_on_chart
        , c.consecutive_days
        , c.entry_status
        , c.peak_date
        , c.entry_rank
        , c.entry_date
        , c.release_date
    FROM {{ ref('stg_charts_songs_daily') }} c
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.chart_date, c.country_code, c.track_uri
        ORDER BY c.chart_rank) = 1
)

-- Chart rows only have the URI used on that day. Join int_song_uri_map to add song_id,
-- so all URIs of a song share one ID and their histories can be combined downstream.
SELECT
    d.chart_date
    , CAST(DATE_TRUNC('week', d.chart_date) AS DATE)    AS week_start        -- Monday of the ISO week
    , d.country_code
    , d.chart_rank
    , d.track_uri
    , COALESCE(m.song_id, d.track_uri)            AS song_id -- URIs missing from songs.csv keep their own URI, can happen if song later removed from Spotify
    , d.track_name
    , d.artist_names
    , d.label
    , d.streams
    , d.entry_date
    , d.release_date
FROM deduplicated d
    LEFT JOIN {{ ref('int_song_uri_map') }} m ON d.track_uri = m.track_uri
