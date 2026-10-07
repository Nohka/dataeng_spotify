{{ config(materialized='view') }}
-- Layer 3 | weekly metric model -> fact_artist_weekly   (Q2)
-- Grain: one row per ISO week x country x artist, for weeks in which the artist charted.
-- Upstream: int_artist_chart_daily (rows), int_date (chart day -> ISO week).
-- Dialect: PostgreSQL.
--
-- FIX 1 (double counting): the source lists the same artist twice on the same day in
-- the same country 3,436 times. The old model used count(*) as days_on_chart, so
-- days_on_chart reached 17 in a 7-day week (619 weekly rows broke the 1..7 test) and
-- presence_score was inflated. The deduped CTE below collapses each day to the
-- artist's BEST rank first, which fixes the day counts and makes the rank measures
-- well defined. (The song model has no equivalent problem: two alias positions there
-- are genuinely different chart entries whose streams must both be summed.)
--
-- FIX 2 (saturated metric): presence_score was days_top20*2 + days_on_chart +
-- (200 - avg_rank)/200. The first two terms cap at 21 per week for anyone permanently
-- in the Top 20, and the only rank-quality term contributes at most 1 per week - which
-- Q2's round() then erased. Result: Bad Bunny tied at exactly 1090 across 17 countries
-- and Q2's "limit 1" returned one of them at random. presence_score is now built from
-- rank_points = sum(201 - best rank of the day), which is additive over days, never
-- saturates, and separates rank 1 from rank 19 by a real margin.

with deduped as (

    -- one row per day: the artist's best position that day
    select
        chart_date,
        country_code,
        artist_uri,
        min(rank) as rank
    from {{ ref('int_artist_chart_daily') }}
    group by 1, 2, 3

),

daily as (

    select
        f.chart_date,
        f.country_code,
        f.artist_uri,
        f.rank,
        (f.rank <= 20) as is_top20,
        d.week_date_key
    from deduped f
    join {{ ref('int_date') }} d on d.full_date = f.chart_date

)

select
    week_date_key,
    country_code,
    artist_uri,
    count(*)                                            as days_on_chart,   -- = distinct days after dedup
    count(*) filter (where is_top20)                    as days_top20,
    min(rank)                                           as best_rank,
    round(avg(rank), 2)                                 as avg_rank,
    -- sum of ranks, so a consumer can build a correctly day-weighted average rank
    -- across weeks. Q2 used to average avg_rank unweighted (a mean of means).
    sum(rank)                                           as rank_sum,
    -- 200 points for rank 1 down to 1 point for rank 200, summed over charted days.
    -- Additive, non-saturating, and interpretable: 1,400 = rank 1 on all seven days.
    sum(201 - rank)                                     as rank_points,
    sum(201 - rank)::numeric / 200                      as presence_score
from daily
group by 1, 2, 3
