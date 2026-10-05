# Core data dictionary

This is the minimal version 1 model documented in the three-page report. The earlier extended model is not required for version 1.

PK = primary key; FK = foreign key; UQ = unique; ? = nullable. Unmarked fields are NOT NULL.

## fact_track_chart_daily - One track-market-date observation.

**date_key INT; market_key SMALLINT; track_key BIGINT** — composite PK and FKs to their dimensions. **chart_rank SMALLINT** — daily position, 1-200. **streams BIGINT?** — reported chart-eligible streams, not unique listeners. **loaded_at TIMESTAMPTZ** — warehouse load time. [4]

## dim_date - One calendar date.

**date_key INT PK** — YYYYMMDD key. **full_date DATE UQ** — UTC chart date. **iso_week_start_date DATE** — Monday beginning the reporting week.

## dim_market - One chart market.

**market_key SMALLINT PK** — warehouse ID. **market_code VARCHAR(16) UQ** — source-normalised code, e.g. EE or GLOBAL. **market_name TEXT** — display name. **is_europe BOOLEAN** — membership in the fixed European panel; false for GLOBAL.

## dim_track - One source track identity.

**track_key BIGINT PK** — warehouse ID. **spotify_track_uri TEXT UQ** — source identifier. **track_name TEXT** — display title. **record_label_current TEXT?** — latest supplied label; normalise spelling, but do not infer ownership.

## dim_artist - One Spotify artist identity.

**artist_key BIGINT PK** — warehouse ID. **spotify_artist_uri TEXT UQ** — source identifier. **artist_name TEXT** — current display name. **musicbrainz_id UUID?** — accepted matched artist identifier.

## bridge_track_artist - One credited artist per track.

**track_key BIGINT; artist_key BIGINT** — composite PK and FKs to track and artist. One row per unique pair; no pipe-separated keys. Presence counts overlap across artists and must not be summed as track totals.

## artist_locality - Current artist-market review.

**artist_key BIGINT; market_key SMALLINT** — composite PK and FKs. **local_status VARCHAR(12)** — local / not_local / unknown. **evidence_url TEXT?** — supporting source. **reviewed_at TIMESTAMPTZ?** — review time. **rule_version TEXT** — classification rule; evidence and review time required for a known status.

## ops_chart_load_daily - One expected market-date load.

**date_key INT; market_key SMALLINT** — composite PK and FKs. **load_status VARCHAR(12)** — complete / partial / missing / failed / unknown. **loaded_at TIMESTAMPTZ** — status update time; raw manifests retain attempt-level details.
