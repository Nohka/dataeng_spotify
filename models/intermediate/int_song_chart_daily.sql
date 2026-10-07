{{ config(
    materialized='incremental',
    unique_key='chart_date',
    incremental_strategy='delete+insert'
) }}
-- Layer 2 | daily song chart rows with the song key resolved
-- Grain: one row per chart day x country x canonical song x rank. rank is part of the
--        grain because the same canonical song can hold two chart positions on one day
--        under two alias URIs (192 such day/country/uri cases exist in the source).
-- Upstream: stg_spotify__charts_songs_daily, int_song_uri_aliases - nothing else.
-- Dialect: PostgreSQL.
--
-- FIX 1 (double counting): unique_key used to be the full 4-column grain, so
-- delete+insert only removed rows whose EXACT rank reappeared. When Spotify revises a
-- day and a song moves 5 -> 6, the stale rank-5 row survived and its streams were
-- counted twice. unique_key is now chart_date alone, which makes delete+insert replace
-- whole day partitions - the only safe pattern for a source that gets revised.
--
-- FIX 2 (NULL FK): an absent label now resolves to the explicit '(unknown)' member of
-- int_label instead of NULL.
--
-- Ingestion window: chart_start_date (a Monday), so every ISO week in scope is whole.

with charts as (

    select *
    from {{ ref('stg_spotify__charts_songs_daily') }}
    where chart_date >= date '{{ var("chart_start_date") }}'
    {% if is_incremental() %}
      -- reload the last 7 chart days each run; the source file is refreshed daily
      and chart_date >= (select max(chart_date) - interval '7 days' from {{ this }})
    {% endif %}

)

select
    c.chart_date,
    c.country_code,
    coalesce(a.track_uri, c.track_uri_raw)      as track_uri,
    coalesce(lower(c.label_name), '(unknown)')  as label_name_norm,
    c.rank,
    c.streams,
    (c.rank <= 10)                              as is_top10,
    (c.rank <= 20)                              as is_top20
from charts c
left join {{ ref('int_song_uri_aliases') }} a
       on a.alias_uri = c.track_uri_raw
