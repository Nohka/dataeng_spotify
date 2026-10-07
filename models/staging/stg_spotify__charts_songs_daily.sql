{{ config(materialized='view') }}
-- 1:1 with charts_songs_daily.csv. Casts, renames and -1 -> NULL only.
-- No filters here: the ingestion window is applied once, in int_song_chart_daily.
-- Dialect: PostgreSQL.

select
    cast(date as date)                          as chart_date,
    cast(country as varchar)                    as country_code,
    cast(rank as integer)                       as rank,
    cast(uri as varchar)                        as track_uri_raw,
    cast(track_name as varchar)                 as track_name,
    cast(artist_names as varchar)               as artist_names,
    cast(artist_uris as varchar)                as artist_uris,
    nullif(btrim(cast(label as varchar)), '')   as label_name,
    cast(streams as bigint)                     as streams,
    cast(peak_rank as integer)                  as peak_rank,
    nullif(cast(previous_rank as integer), -1)  as previous_rank,
    cast(days_on_chart as integer)              as days_on_chart,
    cast(consecutive_days as integer)           as consecutive_days,
    cast(entry_status as varchar)               as entry_status,
    cast(entry_rank as integer)                 as entry_rank,
    cast(entry_date as date)                    as entry_date,
    cast(peak_date as date)                     as peak_date,
    cast(release_date as date)                  as release_date
from {{ source('spotify_raw', 'charts_songs_daily') }}
