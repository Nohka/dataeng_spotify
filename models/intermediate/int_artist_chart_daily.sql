{{ config(
    materialized='incremental',
    unique_key='chart_date',
    incremental_strategy='delete+insert'
) }}
-- Layer 2 | daily artist chart rows, trimmed to what the weekly model needs
-- Grain: one row per chart day x country x artist x rank.
-- Upstream: stg_spotify__charts_artists_daily - nothing else (artist_uri is already
--           the natural key; there is no alias problem on the artist side).
-- Dialect: PostgreSQL.
--
-- FIX (false grain): the grain and unique_key used to be declared as
-- (chart_date, country_code, artist_uri), but the source genuinely lists the same
-- artist twice on the same day in the same country - 3,436 such cases across 57
-- artists, e.g. Essam Sasa at both rank 24 and rank 71 in eg on 2021-10-21. The
-- declared uniqueness test therefore failed. rank is now part of the grain, and
-- int_artist_chart_weekly collapses the duplicates to one row per day before
-- aggregating (see that model).
--
-- unique_key is chart_date so delete+insert replaces whole day partitions, which is
-- revision-safe (see int_song_chart_daily FIX 1).

select
    chart_date,
    country_code,
    artist_uri,
    rank,
    (rank <= 20) as is_top20
from {{ ref('stg_spotify__charts_artists_daily') }}
where chart_date >= date '{{ var("chart_start_date") }}'
{% if is_incremental() %}
  and chart_date >= (select max(chart_date) - interval '7 days' from {{ this }})
{% endif %}
