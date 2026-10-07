{{ config(materialized='view') }}
-- Layer 3 | weekly metric model -> fact_song_weekly   (Q1, Q3, Q4, Q5)
-- Grain: one row per ISO week x country x canonical song, for weeks in which the song charted.
-- Upstream: int_song_chart_daily (rows), int_date (chart day -> ISO week),
--           int_song (release_date). All three joins are now lossless: int_song holds
--           every charting track_uri (including "unknown song" members) and the date
--           spine starts on the same Monday as the chart window.
-- Dialect: PostgreSQL.
--
-- Materialised as a VIEW: fact_song_weekly is the physical table. The old setup
-- materialised the same 6.5M rows twice (int table + mart table) for no benefit.
--
-- Metrics defined HERE only:
--   stream_growth_wow / prev_week_* : NULL unless the song charted the week immediately
--                                     before, so a re-entry never compares to an old week
--   stream_gain_wow                 : absolute week-over-week gain; a new entry gains its
--                                     full weekly_streams. Used by Q4 because a ratio
--                                     explodes on tiny denominators (Q4)
--   heat_score                      : weekly_streams scaled by CLAMPED growth (Q1)
--   days_top10                      : (Q3)
--   weeks_since_release, chart_week_no : (Q5)
--
-- Day counts use count(distinct chart_date): the same song can hold two chart
-- positions on one day under two alias URIs and must count as ONE day. Streams are
-- still summed across both positions, which is correct - they are different entries.

with daily as (

    select
        f.chart_date,
        f.country_code,
        f.track_uri,
        f.label_name_norm,
        f.rank,
        f.streams,
        f.is_top10,
        s.release_date,
        d.week_start_date,
        d.week_date_key
    from {{ ref('int_song_chart_daily') }} f
    join {{ ref('int_date') }} d on d.full_date  = f.chart_date
    join {{ ref('int_song') }} s on s.track_uri = f.track_uri

),

weekly as (

    select
        week_date_key,
        week_start_date,
        country_code,
        track_uri,
        max(release_date)                                       as release_date,     -- constant per song
        -- 5,270 song-weeks carry more than one label spelling. Take the most-streamed
        -- one rather than the alphabetically last, which is what max() used to do.
        (array_agg(label_name_norm order by streams desc nulls last))[1]
                                                                as label_name_norm,
        -- coalesce: 11,400 source chart rows carry no stream count. sum() returns
        -- NULL only when EVERY day of a song-week is missing it, and a NULL additive
        -- measure silently drops out of every downstream SUM and poisons
        -- stream_gain_wow / heat_score. Those weeks become 0 and stay visible through
        -- days_with_streams.
        coalesce(sum(streams), 0)                               as weekly_streams,
        -- distinct DAYS, not rows: a song can hold two positions in one day
        count(distinct case when streams is not null then chart_date end)
                                                                as days_with_streams,
        count(distinct chart_date)                              as days_on_chart,
        count(distinct case when is_top10 then chart_date end)   as days_top10,
        min(rank)                                               as best_rank
    from daily
    group by 1, 2, 3, 4

),

lagged as (

    select
        w.*,
        lag(weekly_streams)  over w_song as prev_week_streams,
        lag(best_rank)       over w_song as prev_best_rank_raw,
        lag(week_start_date) over w_song as prev_charted_week,
        row_number()         over w_song as chart_week_no
    from weekly w
    window w_song as (partition by country_code, track_uri order by week_start_date)

),

with_growth as (

    select
        l.*,
        -- PostgreSQL: date - integer = date, so this is the preceding Monday
        (prev_charted_week = week_start_date - 7)                 as charted_prev_week,
        case when prev_charted_week = week_start_date - 7
             then prev_best_rank_raw end                          as prev_week_best_rank,
        -- Cast to numeric: in PostgreSQL bigint / bigint is INTEGER division and this
        -- ratio would collapse to 0 or -1 for every row.
        case when prev_charted_week = week_start_date - 7
             then weekly_streams::numeric / nullif(prev_week_streams, 0) - 1
             end                                                  as stream_growth_wow
    from lagged l

)

select
    week_date_key,
    country_code,
    track_uri,
    label_name_norm,
    weekly_streams,
    days_with_streams,
    -- NULL when the song did not chart the week before; Q4 coalesces to 0 so a new
    -- entry's gain is its whole week of streams.
    case when charted_prev_week then prev_week_streams end       as prev_week_streams,
    weekly_streams - case when charted_prev_week
                          then coalesce(prev_week_streams, 0) else 0 end
                                                                 as stream_gain_wow,
    days_on_chart,
    days_top10,
    best_rank,
    coalesce(charted_prev_week, false)                           as charted_prev_week,
    prev_week_best_rank,
    stream_growth_wow,
    -- heat_score: weekly_streams scaled by growth, with the growth multiplier CLAMPED
    -- to [-0.5, +1.0]. The old unbounded form (1 + growth) let a song with 8,480
    -- streams and +677% growth (rank 79) beat the actual rank-1 song with 27,811
    -- streams; across 404 complete Estonian weeks it disagreed with the streams leader
    -- 65% of the time, picking songs whose average best rank was 17. Clamping keeps
    -- streams the dominant term - momentum can at most double a song's weight - so the
    -- winner is always a genuinely big song that is also rising.
    round(
        weekly_streams * (1 + least(greatest(coalesce(stream_growth_wow, 0), -0.5), 1.0))
    )                                                            as heat_score,
    chart_week_no,
    -- weeks_since_release: whole ISO weeks between the song's RELEASE week and this
    -- chart week, so the release week itself is 0. The old version measured from this
    -- week's MONDAY to the release date; since releases are overwhelmingly Friday
    -- (29,552 of 57,194 recent releases), 67.6% of songs got -1 in their first chart
    -- week instead of 0, and the accepted_range min_value of -1 codified the bug.
    case when release_date is not null
         then (week_start_date - date_trunc('week', release_date)::date) / 7
         end                                                     as weeks_since_release
from with_growth
