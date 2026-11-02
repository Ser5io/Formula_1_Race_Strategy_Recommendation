-- ===========================================================================
-- TEAM MEMBER: Yousef
-- PHASE 1: BRONZE LAYER (RAW INGESTION & DIAGNOSTIC AUDIT)
-- SCRIPT: 02_yousef_bronze_pits_control.sql
-- TASKS: 1.4 (DDL & Bulk Load), 1.5 (Diagnostics)
--
-- DATASET 3: Pit_Stops.csv -> bronze.raw_pit_stops
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Pit_Stops.csv
-- Approximate Size:  ~283 KB
-- Total Row Count:   2,339 rows (2023-2025 across all Grand Prix races)
-- Source Columns:    16 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, driver_number, lap_number) [0 duplicates]
-- Granularity:       1 record per pit stop event per driver per race lap
--
-- Business & Strategic Purpose:
--   Tracks every pit lane entry, stationary service stop, and exit:
--     1. pit_duration: Total elapsed duration from pit entry line to pit exit line.
--     2. lane_duration: Transit duration spent traveling under pit-lane speed limiter.
--     3. stop_duration: Exact stationary time in pit box during 4-wheel tyre change.
--   Enables calculation of circuit-specific Net Pit Loss (pit transit vs staying on track),
--   crucial for calculating "undercut" / "overcut" delta and deciding BOX NOW vs STAY OUT.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - Natural key is unique with 0 duplicate key groups.
--   - stop_duration is missing in 1,488 rows (~63.6%) due to legacy sensor timing
--     systems lacking optical stationary box triggers. In Silver, stationary time
--     is statistically imputed by isolating lane traversal baselines.
--   - lane_duration and pit_duration are 100% populated.
--
-- ---------------------------------------------------------------------------
-- DATASET 4: Race_Control.csv -> bronze.raw_race_control
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Race_Control.csv
-- Approximate Size:  ~1.02 MB
-- Total Row Count:   6,286 rows (2023-2025 across all Grand Prix races)
-- Source Columns:    17 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, date, message) [8 duplicate rows in raw]
-- Granularity:       1 record per official FIA Race Control message broadcast
--
-- Business & Strategic Purpose:
--   Official timeline of race direction decisions, track hazards, and neutralization:
--     1. Flag states: GREEN, YELLOW, DOUBLE YELLOW, RED, CHEQUERED, BLUE, CLEAR.
--     2. Safety Car deployments: FULL SAFETY CAR (SC) and VIRTUAL SAFETY CAR (VSC).
--     3. System status: DRS ENABLED / DISABLED, PIT EXIT OPEN / CLOSED.
--     4. Judicial & safety events: Driving standards investigations, track limits, debris.
--   Feeds Phase 3 incident ticker and Phase 4 machine learning models estimating
--   historical Safety Car and VSC intervention probabilities per circuit.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - 8 duplicate rows exist where identical broadcast messages were captured
--     at the exact same microsecond timestamp. Deduplicated in Silver.
--   - driver_number is NULL in ~90.8% of rows because general track notifications
--     (e.g., "VIRTUAL SAFETY CAR DEPLOYED") are track-wide rather than driver-specific.
--   - flag is NULL in ~72.3% of rows (for categories like DRS, Other, SessionStatus).
--   - Observed categories: Flag, Other, Drs, SessionStatus, SafetyCar, CarEvent.
--
-- Execution:
--   Run after Mohamed's bronze script:
--   psql -d f1_warehouse -f sql/01_bronze/02_yousef_bronze_pits_control.sql
-- ===========================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.4: DDL Staging Tables
-- ---------------------------------------------------------------------------

-- Table: bronze.raw_pit_stops
-- Description: Raw staging table for Pit_Stops.csv (2,339 rows).
DROP TABLE IF EXISTS bronze.raw_pit_stops;
CREATE TABLE bronze.raw_pit_stops (
    -- Session & Calendar Hierarchy
    year               TEXT,  -- Championship season (2023, 2024, 2025)
    round              TEXT,  -- Round number in championship
    meeting_key        TEXT,  -- Unique meeting key
    meeting_name       TEXT,  -- Grand Prix meeting name
    session_key        TEXT,  -- Unique race session key
    session_name       TEXT,  -- Session name ('Race')
    circuit_short_name TEXT,  -- Short circuit identifier (e.g., Catalunya, Monaco)
    country_name       TEXT,  -- Host country
    -- Event Timestamp & Lap
    date               TEXT,  -- UTC timestamp of pit entry
    pit_duration       TEXT,  -- Total pit lane duration in seconds (entry to exit)
    driver_number      TEXT,  -- Permanent driver racing number
    lap_number         TEXT,  -- Race lap number on which the pit stop occurred
    lane_duration      TEXT,  -- Pit lane traversal duration under limiter in seconds
    stop_duration      TEXT,  -- Stationary service time in pit box in seconds (often NULL)
    name_acronym       TEXT,  -- Three-letter driver acronym (e.g., NOR, BOT)
    team_name          TEXT,  -- Constructor team name
    -- Medallion Audit Lineage Columns
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Pit_Stops.csv'
);

-- Table: bronze.raw_race_control
-- Description: Raw staging table for Race_Control.csv (6,286 rows).
DROP TABLE IF EXISTS bronze.raw_race_control;
CREATE TABLE bronze.raw_race_control (
    -- Session & Calendar Hierarchy
    year               TEXT,  -- Championship season (2023, 2024, 2025)
    round              TEXT,  -- Round number in championship
    meeting_key        TEXT,  -- Unique meeting key
    meeting_name       TEXT,  -- Grand Prix meeting name
    session_key        TEXT,  -- Unique race session key
    session_name       TEXT,  -- Session name ('Race')
    circuit_short_name TEXT,  -- Short circuit identifier
    country_name       TEXT,  -- Host country
    -- Message Event Context
    date               TEXT,  -- UTC timestamp of race control communication
    driver_number      TEXT,  -- Driver racing number if message is driver-specific (else NULL)
    lap_number         TEXT,  -- Estimated race lap at time of broadcast
    category           TEXT,  -- Message classification (Flag, SafetyCar, Drs, SessionStatus, etc.)
    flag               TEXT,  -- Flag type if applicable (GREEN, YELLOW, RED, CHEQUERED, CLEAR)
    scope              TEXT,  -- Geographic scope (Track, Sector, Driver)
    sector             TEXT,  -- Specific track sector index (1, 2, 3, or sub-sector)
    qualifying_phase   TEXT,  -- Qualifying phase (Q1, Q2, Q3; NULL for race sessions)
    message            TEXT,  -- Verbatim official FIA Race Control message text
    -- Medallion Audit Lineage Columns
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Race_Control.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.4: Bulk Load Staging Tables
-- Blank CSV fields become NULL. Source text is otherwise strictly preserved.
-- \copy loads client-side. Server-side COPY equivalents are maintained in docs.
-- ---------------------------------------------------------------------------

\copy bronze.raw_pit_stops (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, pit_duration, driver_number, lap_number, lane_duration, stop_duration, name_acronym, team_name) FROM '/home/mohamed/F1/raw_data/Pit_Stops.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_race_control (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, driver_number, lap_number, category, flag, scope, sector, qualifying_phase, message) FROM '/home/mohamed/F1/raw_data/Race_Control.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.5: Diagnostics & Data Profiling
-- ---------------------------------------------------------------------------

-- Pit stops row count and distinct sessions per season
SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_pit_stops
GROUP BY year
ORDER BY year;

-- Profiling missing stationary stop_duration vs lane_duration in raw_pit_stops
-- Expected: stop_duration has 1,488 missing values (~63.6%).
SELECT
    COUNT(*) AS row_count,
    COUNT(*) FILTER (WHERE stop_duration IS NULL OR BTRIM(stop_duration) = '') AS stop_duration_null,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE stop_duration IS NULL OR BTRIM(stop_duration) = '')
        / NULLIF(COUNT(*), 0),
        2
    ) AS stop_duration_null_pct,
    COUNT(*) FILTER (WHERE lane_duration IS NULL OR BTRIM(lane_duration) = '') AS lane_duration_null,
    COUNT(*) FILTER (WHERE pit_duration IS NULL OR BTRIM(pit_duration) = '') AS pit_duration_null,
    COUNT(*) FILTER (WHERE driver_number IS NULL OR BTRIM(driver_number) = '') AS driver_number_null
FROM bronze.raw_pit_stops;

-- Race control message volume and distinct sessions per season
SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_race_control
GROUP BY year
ORDER BY year;

-- Driver number and flag NULL distributions in race control
-- Large percentage of track-wide messages do not target a specific driver
SELECT
    COUNT(*) AS row_count,
    COUNT(*) FILTER (WHERE driver_number IS NULL OR BTRIM(driver_number) = '') AS driver_number_null,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE driver_number IS NULL OR BTRIM(driver_number) = '')
        / NULLIF(COUNT(*), 0),
        2
    ) AS driver_number_null_pct,
    COUNT(*) FILTER (WHERE flag IS NULL OR BTRIM(flag) = '') AS flag_null,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE flag IS NULL OR BTRIM(flag) = '')
        / NULLIF(COUNT(*), 0),
        2
    ) AS flag_null_pct
FROM bronze.raw_race_control;

-- Distribution of message categories
SELECT COALESCE(NULLIF(BTRIM(category), ''), '(blank)') AS category, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

-- Distribution of flag conditions
SELECT COALESCE(NULLIF(BTRIM(flag), ''), '(blank)') AS flag, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

-- Distribution of message scope (Track vs Sector vs Driver)
SELECT COALESCE(NULLIF(BTRIM(scope), ''), '(blank)') AS scope, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

-- Duplicate natural-key check on raw_pit_stops. Expected: 0 duplicate rows.
SELECT
    session_key,
    driver_number,
    lap_number,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_pit_stops
GROUP BY session_key, driver_number, lap_number
HAVING COUNT(*) > 1;
