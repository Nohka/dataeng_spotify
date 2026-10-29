-- Weekly chart presence per artist x country. One row per week_start x country x artist_uri.
-- presence_points = SUM(201 - rank): rank 1 = 200 points per day, rank 200 = 1 point.
-- All metrics are additive (or can be rebuilt from additive ones), so any period can be
-- calculated by summing weeks: e.g. Q1 over the whole window = SUM(presence_points).
-- 'global' is excluded: it is a worldwide chart, not a country.

WITH weekly AS (
    SELECT
        CAST(DATE_TRUNC('week', c.chart_date) AS DATE)  AS week_start      -- Monday of the ISO week
        , c.country_code
        , c.artist_uri
        , ARG_MAX(c.artist_name, c.chart_date)          AS chart_artist_name   -- latest spelling on the chart
        , COUNT(*)                                      AS chart_days
        , MIN(c.chart_rank)                             AS best_rank
        , SUM(c.chart_rank)                             AS rank_sum            -- to rebuild avg_rank over any period
        , SUM(201 - c.chart_rank)                       AS presence_points -- afterwards we can do RANK() OVER (PARTITION BY artist_name, counrty ORDER BY SUM(w.presence_points) DESC)
          -- Then for whichever period we build the "presence" metric, it will be a combination of fo rhow many weeks it charted and at which rank (more weeks & better position -> stronger presence)
    FROM {{ ref('int_charts_artists_daily') }} c
    WHERE 0=0
        AND c.country_code <> 'global'
    GROUP BY
        CAST(DATE_TRUNC('week', c.chart_date) AS DATE)
        , c.country_code
        , c.artist_uri
)

, country_weeks AS (
    -- number of chart days each country has in a week: 7 = complete week
    -- Calculated on a country level: the number of days with at least one artist on that country’s chart
    SELECT
        CAST(DATE_TRUNC('week', c.chart_date) AS DATE)  AS week_start
        , c.country_code
        , COUNT(DISTINCT c.chart_date)                  AS chart_days_in_week
    FROM {{ ref('int_charts_artists_daily') }} c
    WHERE 0=0
        AND c.country_code <> 'global'
    GROUP BY
        CAST(DATE_TRUNC('week', c.chart_date) AS DATE)
        , c.country_code
)

SELECT
    w.week_start
    , w.country_code
    , w.artist_uri
    , COALESCE(a.artist_name, w.chart_artist_name)      AS artist_name
    , w.chart_days
    , w.best_rank
    , w.rank_sum
    , ROUND(w.rank_sum / w.chart_days, 1)               AS avg_rank
    , w.presence_points
    , cw.chart_days_in_week = 7                         AS is_complete_week
    -- 1 = the country where this artist's presence was strongest in this week
    , RANK() OVER (
        PARTITION BY w.artist_uri, w.week_start
        ORDER BY w.presence_points DESC)             AS country_rank_for_artist_in_week -- artist's presence rank per week and country
FROM weekly w
    INNER JOIN country_weeks cw
        ON  cw.country_code = w.country_code
        AND cw.week_start   = w.week_start
    LEFT JOIN {{ ref('stg_artists') }} a USING (artist_uri) -- The join gives each artist one consistent name across all weeks and countries.
