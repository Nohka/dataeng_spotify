{{ config(materialized='table') }}
-- Layer 1 | song dimension (SCD 1, full rebuild)
-- Grain: one row per canonical song; natural key track_uri.
-- Dialect: PostgreSQL.
--
-- FIX 1 (data loss): the old version deleted every song whose release_date fell
-- outside 2000-01-01 .. +1y. That removed 4,255 songs of which only 5 were truly
-- implausible (pre-1900); the rest were legitimate catalogue. Because
-- int_song_chart_weekly inner-joins this model, it also erased 1,066,449 chart rows
-- for songs such as "Every Breath You Take" (1983), "All I Want for Christmas Is You"
-- (1994) and "Last Christmas" (1984) - exactly the catalogue titles that chart every
-- December. Rows are now always kept; only an implausible DATE is nulled out, so a
-- bad date can no longer corrupt weeks_since_release and no chart row is lost.
--
-- FIX 2 (data loss): songs that chart but are absent from songs.csv used to be
-- dropped by the same inner join. They are now added as "unknown song" members, so
-- the fact keeps full referential integrity and fact_song_weekly reconciles exactly
-- to int_song_chart_daily.
--
-- FIX 3 (release_date accuracy): songs.csv carries ONE release date, which for a
-- re-released track is the date of the LATEST release it appears on. That made songs
-- look as if they charted months before they existed (e.g. a track charting from
-- 2026-08-10 with a songs.csv date of 2026-08-27). The chart rows carry the release
-- date as published AT THE TIME the song charted, so the earliest date observed
-- anywhere is the best available estimate of the original release. Taking the
-- earliest cuts rows with weeks_since_release < -8 from 69 to 2.

{% set plausible_lo = "date '1900-01-01'" %}
{% set plausible_hi = "(current_date + interval '1 year')::date" %}

with
-- Earliest release date ever published on a chart row for this song, alias-resolved
-- the same way int_song_chart_daily resolves it so the two models always agree.
chart_release as (

    select
        coalesce(a.track_uri, c.track_uri_raw) as track_uri,
        min(c.release_date) filter (
            where c.release_date between {{ plausible_lo }} and {{ plausible_hi }}
        )                                      as first_chart_release_date,
        true                                   as charted_in_window
    from {{ ref('stg_spotify__charts_songs_daily') }} c
    left join {{ ref('int_song_uri_aliases') }} a
           on a.alias_uri = c.track_uri_raw
    where c.chart_date >= date '{{ var("chart_start_date") }}'
    group by 1

),

known as (

    select
        s.track_uri,
        s.track_name,
        (string_to_array(s.artist_names, '|'))[1] as primary_artist_name,
        -- Keep the row, null an impossible date. 1900 is the plausibility floor:
        -- recorded music predates Spotify, so an old date is normally correct.
        least(
            case when s.release_date between {{ plausible_lo }} and {{ plausible_hi }}
                 then s.release_date end,
            cr.first_chart_release_date
        )                                         as release_date,
        false                                     as is_unknown_song
    from {{ ref('stg_spotify__songs') }} s
    left join chart_release cr on cr.track_uri = s.track_uri

)

select track_uri, track_name, primary_artist_name, release_date, is_unknown_song
from known

union all

-- Canonical URIs that charted inside the window but have no row in songs.csv.
select
    cr.track_uri,
    cast(null as varchar)        as track_name,
    cast(null as varchar)        as primary_artist_name,
    cr.first_chart_release_date  as release_date,
    true                         as is_unknown_song
from chart_release cr
where not exists (select 1 from {{ ref('stg_spotify__songs') }} k where k.track_uri = cr.track_uri)
