{{ config(materialized='table') }}
-- Dimension | SCD 1. Grain: one canonical song. PK track_uri (natural key).
-- Holds every song that charts, including "unknown song" members for chart URIs that
-- songs.csv does not describe (is_unknown_song = true), so fact_song_weekly never
-- loses a row to a missing dimension member.
select * from {{ ref('int_song') }}
