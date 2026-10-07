{{ config(materialized='table') }}
-- Fact | grain: ISO week x country x artist  (country_code is a degenerate dimension)
-- Periodic snapshot: one row per artist/country/ISO week in which the artist charted.
-- Physical table; int_artist_chart_weekly is a view, so the rows are materialised once.
-- NOTE: see fact_song_weekly on the 'global' pseudo-country.
select * from {{ ref('int_artist_chart_weekly') }}
