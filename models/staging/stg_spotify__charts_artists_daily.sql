{{ config(materialized='view') }}
-- 1:1 with charts_artists_daily.csv. Casts, renames and -1 -> NULL only.
-- No filters here: the ingestion window is applied once, in int_artist_chart_daily.
-- Dialect: PostgreSQL.

select
    cast(date as date)                          as chart_date,
    cast(country as varchar)                    as country_code,
    cast(rank as integer)                       as rank,
    cast(uri as varchar)                        as artist_uri,
    cast(artist_name as varchar)                as artist_name,
    cast(peak_rank as integer)                  as peak_rank,
    nullif(cast(previous_rank as integer), -1)  as previous_rank,
    cast(days_on_chart as integer)              as days_on_chart,
    cast(consecutive_days as integer)           as consecutive_days,
    cast(entry_status as varchar)               as entry_status,
    cast(entry_rank as integer)                 as entry_rank,
    cast(entry_date as date)                    as entry_date,
    cast(peak_date as date)                     as peak_date
from {{ source('spotify_raw', 'charts_artists_daily') }}
