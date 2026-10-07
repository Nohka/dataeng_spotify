{{ config(materialized='table') }}
-- Layer 1 | artist dimension (SCD 1, full rebuild)
-- Grain: one row per artist that charted inside the ingestion window; natural key artist_uri.
-- artist_uri (not artist_name) is the key: 329 names map to more than one artist
-- (e.g. five different "Kali" profiles), and names get respelled over time.
-- Name comes from artists.csv when present, otherwise the latest spelling seen on a chart.
-- Listener counts / ranks are measures, not attributes, and stay out of the dimension.
-- Dialect: PostgreSQL - DISTINCT ON replaces DuckDB's arg_max().

with charted as (

    -- DISTINCT ON keeps the first row per artist_uri after ordering, i.e. the most
    -- recent chart spelling. This is the PostgreSQL equivalent of
    -- arg_max(artist_name, chart_date).
    select distinct on (artist_uri)
        artist_uri,
        artist_name as chart_artist_name
    from {{ ref('stg_spotify__charts_artists_daily') }}
    where chart_date >= date '{{ var("chart_start_date") }}'
    order by artist_uri, chart_date desc

)

select
    c.artist_uri,
    coalesce(a.artist_name, c.chart_artist_name) as artist_name
from charted c
left join {{ ref('stg_spotify__artists') }} a
       on a.artist_uri = c.artist_uri
