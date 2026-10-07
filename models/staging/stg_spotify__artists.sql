{{ config(materialized='view') }}
-- 1:1 with artists.csv. Casts and renames only.
-- Listener columns are carried here for completeness but are deliberately NOT used
-- downstream: they are daily-changing measures, not dimension attributes.
-- Dialect: PostgreSQL.

select
    cast(artist_uri as varchar)                        as artist_uri,
    cast(artist_name as varchar)                       as artist_name,
    cast(monthly_listeners as bigint)                  as monthly_listeners,
    cast(monthly_listeners_rank as integer)            as listener_rank,
    cast(monthly_listeners_peak_rank as integer)       as listener_peak_rank,
    cast(monthly_listeners_peak_listeners as bigint)   as listener_peak_listeners
from {{ source('spotify_raw', 'artists') }}
