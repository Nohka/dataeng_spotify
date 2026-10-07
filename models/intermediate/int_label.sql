{{ config(materialized='table') }}
-- Layer 1 | label dimension (SCD 1)
-- Grain: one row per normalised label name; natural key label_name_norm = lower(btrim(label)).
-- Built from the chart rows, which is where the fact's label comes from, so referential
-- integrity holds by construction. Windowed by the same var as the fact.
-- Dialect: PostgreSQL - row_number() subquery instead of DuckDB's QUALIFY.
--
-- FIX 1 (NULL FK in a fact): 43,245 chart rows have no label at all. They used to
-- produce a NULL label_name_norm on the fact, which a relationships test silently
-- ignores. An explicit '(unknown)' member is added here and the fact coalesces to
-- it, so every fact row has a real FK and unlabelled streams stay countable.
--
-- FIX 2 (Q3 fragmentation): lower() alone normalises nothing - the dimension holds
-- 28,564 entries including 119 "sony music%" and 223 "universal%" variants, which
-- splits a major's credit across dozens of rows and let "WM Finland" out-rank
-- Columbia. label_group collapses the "<parent>/<sub-label>" pattern that the source
-- uses (e.g. "Sony Music Latin/Duars Entertainment" -> "sony music latin") onto its
-- first segment. This is a heuristic, not a curated parent mapping: it merges
-- sub-labels into their stated parent but cannot know that "Columbia" belongs to
-- Sony. Q3 reports by label_group and says so.

with counted as (

    select
        lower(label_name)   as label_name_norm,
        label_name,
        count(*)            as occurrences
    from {{ ref('stg_spotify__charts_songs_daily') }}
    where label_name is not null
      and chart_date >= date '{{ var("chart_start_date") }}'
    group by 1, 2

),

ranked as (

    select
        label_name_norm,
        label_name,
        row_number() over (
            partition by label_name_norm
            order by occurrences desc, label_name
        ) as rn
    from counted

)

select
    label_name_norm,
    label_name,                                                      -- most frequent raw spelling
    lower(btrim(split_part(label_name, '/', 1))) as label_group_norm,
    btrim(split_part(label_name, '/', 1))        as label_group
from ranked
where rn = 1

union all

select
    '(unknown)'  as label_name_norm,
    '(Unknown)'  as label_name,
    '(unknown)'  as label_group_norm,
    '(Unknown)'  as label_group
