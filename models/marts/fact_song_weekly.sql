{{ config(materialized='table') }}
-- Fact | grain: ISO week x country x canonical song  (country_code is a degenerate dimension)
-- Periodic snapshot: one row per song/country/ISO week in which the song charted.
-- Physical table; int_song_chart_weekly is a view, so the rows are materialised once.
-- NOTE: country_code mixes real ISO-2 markets with the synthetic 'global' chart, whose
-- streams overlap the per-country rows. Every query that counts or sums across
-- countries must exclude 'global' (all five demo queries do).
select * from {{ ref('int_song_chart_weekly') }}
