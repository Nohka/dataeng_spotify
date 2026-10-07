{{ config(materialized='view') }}
-- 1:1 with songs.csv. Casts and renames only; the pipe-separated lists stay raw strings
-- (int_song_uri_aliases and int_song are responsible for splitting them).
-- Dialect: PostgreSQL.

select
    cast(track_uri as varchar)                  as track_uri,
    cast(track_name as varchar)                 as track_name,
    cast(artist_names as varchar)               as artist_names,
    cast(artist_uris as varchar)                as artist_uris,
    nullif(btrim(cast(label as varchar)), '')   as label_name,
    cast(release_date as date)                  as release_date,
    cast(all_uris as varchar)                   as all_uris
from {{ source('spotify_raw', 'songs') }}
