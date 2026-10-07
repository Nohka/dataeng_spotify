{{ config(materialized='table') }}
-- Dimension | SCD 1. Grain: one artist that charted in the window. PK artist_uri.
-- artist_name is NOT unique (329 names map to several artists), so always filter and
-- group by artist_uri.
select * from {{ ref('int_artist') }}
