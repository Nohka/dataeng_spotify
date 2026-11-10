-- Singular test | the safeguard that was missing.
--
-- The two silent data-loss bugs (a date spine that did not cover the data, and a
-- release-date filter that deleted the catalogue) removed 18.5% of chart rows and
-- 15.4% of all streams from the fact, and NOT ONE declared test noticed. Row-level
-- tests cannot catch loss - only a reconciliation can.
--
-- Asserts that every stream in int_song_chart_daily inside the window reaches
-- fact_song_weekly. Returns a row (= failure) if any week disagrees.

with source_weekly as (

    select
        d.week_date_key,
        f.country_code,
        sum(f.streams) as streams
    from {{ ref('int_song_chart_daily') }} f
    join {{ ref('int_date') }} d on d.full_date = f.chart_date
    group by 1, 2

),

fact_weekly as (

    select
        week_date_key,
        country_code,
        sum(weekly_streams) as streams
    from {{ ref('fact_song_weekly') }}
    group by 1, 2

)

select
    coalesce(s.week_date_key, f.week_date_key) as week_date_key,
    coalesce(s.country_code,  f.country_code)  as country_code,
    s.streams                                  as source_streams,
    f.streams                                  as fact_streams
from source_weekly s
full outer join fact_weekly f
  on  f.week_date_key = s.week_date_key
  and f.country_code  = s.country_code
where coalesce(s.streams, 0) <> coalesce(f.streams, 0)
