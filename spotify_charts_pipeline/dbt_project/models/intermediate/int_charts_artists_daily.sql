-- Daily artist chart rows, cleaned. One row per chart_date x country x artist_uri.
-- Discovery: the source sometimes lists a 2nd artist with the same name under another artist's URI.
-- On those days the URI appears twice in one country, with two different chart histories
-- (a chart history = artist_uri x country x entry_date). Examples: Luis Gabriel (ro),
-- Inkos'yamagcokama (za), VCT (vn).
-- Decision: the oldest history owns the URI; all other histories of that URI and country
-- ("side histories") are deleted. Moving them to the right URI is not reliable (see VCT).

WITH histories AS (
    -- PURPOSE: turns the daily chart rows into one row per chart history. A chart history is one artist’s run on one country’s chart, and the
    -- source marks it with entry_date: every day of the same run carries the same entry_date (a re-entry can start a new one)
    -- WHY NEEDED: the model decides which rows to delete per history, not per day
    SELECT
        c.artist_uri
        , c.country_code
        , c.entry_date
        , COUNT(*)              AS chart_days -- counts how many daily rows each history has
              -- Example: VCT in Vietnam
                -- the one with URI= 7yqu… and entry date = 2021-10-21 => chart_days = 195 (this combo had 195 days in the chart)
                -- the one with URI= 7yqu… and entry date = 2026-01-21 => chart_days = 15 (this combo had 15 days in the chart)
    FROM {{ ref('stg_charts_artists_daily') }} c
    GROUP BY ALL
)

, collisions AS (
    -- PURPOSE: finds the artist and country pairs where the same URI appeared more than once on at least one chart day.
    -- WHY NEEDED: It limits the side-history check to pairs that actually had a collision. Without it, side_histories would treat every
      --artist with more than one entry_date in a country as having a side history. That would be wrong for real re-entries. If an artist
      --drops off the chart and later comes back with a new entry_date, they have two histories, but never on the same day.
    SELECT DISTINCT
        c.artist_uri
        , c.country_code
    FROM {{ ref('stg_charts_artists_daily') }} c
    GROUP BY -- creates one group per artist, country and day. Normally each group has one row
        c.chart_date
        , c.country_code
        , c.artist_uri
    HAVING COUNT(*) > 1 -- keeps only the groups with more than one row, which are the double days
)

, side_histories AS (
    -- PURPOSE: builds the list of histories to delete: for each pair with a collision, every history except the oldest.
    -- within a colliding artist x country, the oldest history is the real one; all others are side histories
    SELECT
        h.artist_uri
        , h.country_code
        , h.entry_date
    FROM histories h
        INNER JOIN collisions co USING (artist_uri, country_code) -- only keep the artist x country pairs that had multiple entries for any chart date
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY h.artist_uri , h.country_code
        ORDER BY
            h.entry_date            -- the oldest chart history owns the URI
            , h.chart_days DESC     -- tie-break: the longer history wins
    ) > 1 -- keep all but the oldest history (oldest is main, here we define all side histories)
)

SELECT
    c.*
FROM {{ ref('stg_charts_artists_daily') }} c
    -- keep only rows that do not belong to a side history
    LEFT JOIN side_histories s
        ON  s.artist_uri   = c.artist_uri
        AND s.country_code = c.country_code
        AND s.entry_date   = c.entry_date
WHERE 0=0
    AND s.artist_uri IS NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY
        c.chart_date
        , c.country_code
        , c.artist_uri
    ORDER BY c.chart_rank
) = 1 -- if dupliactes for same URI & entry date, take the row with highest rank (best position) for the given day
