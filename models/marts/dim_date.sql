{{ config(materialized='table') }}
-- Dimension | Static. Grain: one calendar day. PK date_key (INT yyyymmdd).
-- Role-playing: both facts join week_date_key -> date_key, i.e. to the row for the
-- ISO-week Monday. Calendar attributes (year/quarter/month) therefore describe that
-- MONDAY, not the whole week. 7 of the 92 weeks in the current spine straddle a
-- quarter boundary, so such a
-- week is attributed wholly to its Monday's quarter - Q3 documents this.
select * from {{ ref('int_date') }}
