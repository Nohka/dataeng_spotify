-- Staging: one row per artist. Only renames and data types.
-- Note: names like 'N/A' and 'None' are real values in the source, not NULLs.

SELECT
    artist_uri
    , artist_name
    , CAST(monthly_listeners AS BIGINT)                 AS monthly_listeners
    , CAST(monthly_listeners_rank AS INTEGER)           AS monthly_listeners_rank
    , CAST(monthly_listeners_peak_rank AS INTEGER)      AS monthly_listeners_peak_rank
    , CAST(monthly_listeners_peak_listeners AS BIGINT)  AS monthly_listeners_peak_listeners
FROM {{ source('spotify', 'artists') }}
