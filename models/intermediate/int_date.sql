{{ config(materialized='table') }}
-- Layer 1 | date dimension (Static, standalone - no upstream models)
-- Grain: one row per calendar day.
-- Dialect: PostgreSQL - generate_series over timestamps, to_char for the keys.
--
-- FIX 1 (data loss): the spine used to start at 2019-01-01 while the song chart
-- actually starts 2017-01-01, so the inner join in int_song_chart_weekly silently
-- discarded 7,170,112 chart rows (16% of the file). The spine is now driven by the
-- same var as the chart models, so the two can never disagree again.
--
-- FIX 2 (broken FK): 2019-01-01 is a Tuesday, so the ISO-week Monday of the first
-- in-scope days was 2018-12-31 - a date OUTSIDE the spine. 12,460 fact rows carried
-- week_date_key = 20181231 with no dim_date row, and the relationships test failed.
-- chart_start_date is now required to be a Monday (2026-01-05) and the assertion
-- below fails the build if it is not, so week_date_key is always inside the spine.
--
-- Deliberately contains no current_date-dependent flags: "this week" is resolved
-- at query time, otherwise the column would go stale between rebuilds.

{% set start_date = var('chart_start_date') %}

{# Build-time guard: the window must begin on a Monday so that every ISO week in
   scope is complete and every week_start_date resolves inside the spine. #}
{% if execute %}
  {% set dow = modules.datetime.datetime.strptime(start_date, '%Y-%m-%d').weekday() %}
  {% if dow != 0 %}
    {{ exceptions.raise_compiler_error(
         "chart_start_date (" ~ start_date ~ ") must be a Monday; got weekday index " ~ dow) }}
  {% endif %}
{% endif %}

with days as (

    select cast(d as date) as full_date
    from generate_series(
             date '{{ start_date }}',
             -- end on the Sunday of the week one year out, so the last ISO week is whole
             (date_trunc('week', current_date + interval '1 year') + interval '6 days')::date,
             interval '1 day'
         ) as t(d)

),

enriched as (

    select
        full_date,
        date_trunc('week', full_date)::date as week_start_date   -- PostgreSQL: Monday-based
    from days

)

select
    cast(to_char(full_date, 'YYYYMMDD') as integer)      as date_key,
    full_date,
    extract(year    from full_date)::int                 as year,
    extract(quarter from full_date)::int                 as quarter,
    extract(month   from full_date)::int                 as month,
    extract(isoyear from full_date)::int                 as iso_year,
    extract(week    from full_date)::int                 as iso_week,
    week_start_date,
    (week_start_date + 6)                                as week_end_date,
    cast(to_char(week_start_date, 'YYYYMMDD') as integer) as week_date_key
from enriched
