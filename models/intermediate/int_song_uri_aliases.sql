{{ config(materialized='table') }}
-- Layer 1 | key resolution
-- Grain: one row per release-specific track URI -> canonical track_uri.
-- songs.all_uris is pipe-separated and always contains the canonical URI itself
-- (verified: 0 of 215,184 songs are missing their own URI from the list).
-- Dialect: PostgreSQL - string_to_array + unnest via LATERAL.
--
-- FIX: the tie-break now prefers the row where the alias IS the canonical URI.
-- Today no alias maps to two songs, so this is a no-op guard, but if the source
-- ever publishes an overlapping all_uris list the old "order by track_uri"
-- could have re-pointed a song's own URI at a different song.

with exploded as (

    select
        s.track_uri,
        btrim(a.alias_uri) as alias_uri
    from {{ ref('stg_spotify__songs') }} s
    cross join lateral unnest(string_to_array(s.all_uris, '|')) as a(alias_uri)
    where s.all_uris is not null

),

ranked as (

    select
        alias_uri,
        track_uri,
        row_number() over (
            partition by alias_uri
            order by case when alias_uri = track_uri then 0 else 1 end, track_uri
        ) as rn
    from exploded
    where alias_uri <> ''

)

select alias_uri, track_uri
from ranked
where rn = 1
