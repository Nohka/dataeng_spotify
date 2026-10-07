-- Singular test | no daily chart row may be lost between layer 2 and the fact.
-- Counts distinct (week, country, song) combinations on both sides.

with source_grain as (

    select count(*) as n
    from (
        select distinct d.week_date_key, f.country_code, f.track_uri
        from {{ ref('int_song_chart_daily') }} f
        join {{ ref('int_date') }} d on d.full_date = f.chart_date
    ) x

),

fact_grain as (
    select count(*) as n from {{ ref('fact_song_weekly') }}
)

select s.n as source_rows, f.n as fact_rows
from source_grain s, fact_grain f
where s.n <> f.n
