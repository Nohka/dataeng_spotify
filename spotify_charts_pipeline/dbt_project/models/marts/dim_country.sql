-- Gold layer: country dimension, from the ISO 3166 seed. Key country_code joins to the marts' country_code.
-- Codes are lowercased to match the chart data. 'global' is added for the worldwide chart.

SELECT
      LOWER("alpha-2")      AS country_code
    , UPPER("alpha-2")      AS iso_alpha2
    , "alpha-3"             AS iso_alpha3
    , name                  AS country_name
    , NULLIF(region, '')     AS region
    , NULLIF("sub-region", '') AS sub_region
FROM {{ ref('countries') }}

UNION ALL

SELECT 'global', NULL, NULL, 'Global', NULL, NULL
