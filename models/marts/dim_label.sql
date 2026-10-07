{{ config(materialized='table') }}
-- Dimension | SCD 1. Grain: one normalised label name. PK label_name_norm.
-- Includes an explicit '(unknown)' member so unlabelled chart rows keep a valid FK.
-- label_group_norm collapses "<parent>/<sub-label>" onto the parent segment; it is a
-- heuristic, not a curated label hierarchy.
select * from {{ ref('int_label') }}
