-- Minimal report v1 schema, PostgreSQL. Design SQL, not source-populated.
-- This namespace is separate from the earlier, larger music schema.
-- Assign surrogate keys in ETL; preserve source URI-to-key mappings.
BEGIN;
CREATE SCHEMA IF NOT EXISTS music_report_v1;
SET search_path TO music_report_v1, public;

CREATE TABLE dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    iso_week_start_date DATE NOT NULL,
    CHECK (iso_week_start_date = full_date - (EXTRACT(ISODOW FROM full_date)::INTEGER - 1))
);
CREATE TABLE dim_market (
    market_key SMALLINT PRIMARY KEY,
    market_code VARCHAR(16) NOT NULL UNIQUE,
    market_name TEXT NOT NULL,
    is_europe BOOLEAN NOT NULL,
    CHECK (market_code <> 'GLOBAL' OR is_europe = FALSE)
);
CREATE TABLE dim_track (
    track_key BIGINT PRIMARY KEY,
    spotify_track_uri TEXT NOT NULL UNIQUE,
    track_name TEXT NOT NULL,
    record_label_current TEXT
);
CREATE TABLE dim_artist (
    artist_key BIGINT PRIMARY KEY,
    spotify_artist_uri TEXT NOT NULL UNIQUE,
    artist_name TEXT NOT NULL,
    musicbrainz_id UUID
);
CREATE TABLE bridge_track_artist (
    track_key BIGINT NOT NULL REFERENCES dim_track(track_key),
    artist_key BIGINT NOT NULL REFERENCES dim_artist(artist_key),
    PRIMARY KEY (track_key, artist_key)
);
CREATE TABLE artist_locality (
    artist_key BIGINT NOT NULL REFERENCES dim_artist(artist_key),
    market_key SMALLINT NOT NULL REFERENCES dim_market(market_key),
    local_status VARCHAR(12) NOT NULL
        CHECK (local_status IN ('local', 'not_local', 'unknown')),
    evidence_url TEXT,
    reviewed_at TIMESTAMPTZ,
    rule_version TEXT NOT NULL,
    PRIMARY KEY (artist_key, market_key),
    CHECK (local_status = 'unknown'
        OR (NULLIF(BTRIM(evidence_url), '') IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE TABLE fact_track_chart_daily (
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
    market_key SMALLINT NOT NULL REFERENCES dim_market(market_key),
    track_key BIGINT NOT NULL REFERENCES dim_track(track_key),
    chart_rank SMALLINT NOT NULL CHECK (chart_rank BETWEEN 1 AND 200),
    streams BIGINT CHECK (streams >= 0),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (date_key, market_key, track_key)
);
CREATE TABLE ops_chart_load_daily (
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
    market_key SMALLINT NOT NULL REFERENCES dim_market(market_key),
    load_status VARCHAR(12) NOT NULL
        CHECK (load_status IN ('complete', 'partial', 'missing', 'failed', 'unknown')),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (date_key, market_key)
);
CREATE INDEX track_chart_market_date ON fact_track_chart_daily(market_key, date_key);
CREATE INDEX bridge_by_artist ON bridge_track_artist(artist_key, track_key);

COMMENT ON SCHEMA music_report_v1 IS
    'Minimal proposed radio-trends warehouse: current descriptive attribution, UTC daily charts, Monday-Sunday reporting weeks.';
COMMENT ON TABLE fact_track_chart_daily IS
    'One observed track appearance per UTC chart date and market; absent rows do not establish zero streams.';
COMMENT ON COLUMN fact_track_chart_daily.streams IS
    'Reported chart-eligible streams, not all Spotify streams or unique listeners; NULL means unknown.';
COMMENT ON COLUMN dim_market.is_europe IS
    'Membership in the fixed version 1 European analysis panel. Seed the complete agreed panel before computing comparisons.';
COMMENT ON COLUMN dim_track.record_label_current IS
    'Latest supplied label attribution; not historical label ownership.';
COMMENT ON TABLE artist_locality IS
    'Current reviewed artist-market association under a documented rule. Type 1; retain raw evidence snapshots separately.';
COMMENT ON TABLE ops_chart_load_daily IS
    'One expected daily track-chart load per market/date. Mark complete only after source reconciliation.';
COMMIT;
