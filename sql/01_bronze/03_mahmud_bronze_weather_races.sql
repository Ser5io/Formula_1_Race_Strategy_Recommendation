-- ===========================================================================
-- TEAM MEMBER: Mahmud
-- PHASE 1: BRONZE LAYER (RAW INGESTION & DIAGNOSTIC AUDIT)
-- SCRIPT: 03_mahmud_bronze_weather_races.sql
-- TASKS: 1.6 (DDL & Bulk Load), 1.7 (Diagnostics)
--
-- DATASET 5: Weather.csv -> bronze.raw_weather
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Weather.csv
-- Approximate Size:  ~4.24 MB
-- Total Row Count:   34,420 rows (2023-2025 across all Grand Prix weekend sessions)
-- Source Columns:    16 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, date) [28 duplicate rows in raw]
-- Granularity:       1 record per weather measurement (~1 min interval) per session
--
-- Business & Strategic Purpose:
--   High-resolution meteorological station telemetry at circuit perimeter:
--     1. track_temperature: Track surface heat (deg C). Primary physical driver
--        of tyre thermal degradation, graining, and blistering thresholds.
--     2. air_temperature & humidity: Ambient thermal state and air density.
--     3. pressure: Atmospheric pressure (mbar), affecting aero downforce and cooling.
--     4. wind_speed & wind_direction: Wind velocity vector affecting braking points
--        and straight-line aerodynamic stability.
--     5. rainfall: Precipitation detection sensor triggering wet/intermediate tyre crossover.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - Ingestion: Staged as 100% TEXT. 0 NULL values across all sensor columns.
--   - Session coverage: Captures all weekend sessions (Practice 1, 2, 3,
--     Qualifying, Sprint Qualifying, Sprint, and Race). Silver filters for 'Race'.
--   - 28 duplicate (session_key, date) readings exist in raw data and are
--     deduplicated in Silver using windowed row numbering.
--
-- ---------------------------------------------------------------------------
-- DATASET 6: Races.csv -> bronze.raw_races
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Races.csv
-- Approximate Size:  ~15.1 KB
-- Total Row Count:   70 rows (2023: 22 | 2024: 24 | 2025: 24 Grand Prix races)
-- Source Columns:    22 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       session_key [0 duplicates across all 70 race meetings]
-- Granularity:       1 record per Grand Prix race event
--
-- Business & Strategic Purpose:
--   Master calendar and circuit dimension defining event hierarchy:
--     1. Circuit identification: circuit_short_name, circuit_type (Permanent vs
--        Temporary - Street). Street circuits exhibit higher Safety Car frequency
--        and slower pit transit speeds.
--     2. Geographic metadata: country_code, country_name, location, gmt_offset.
--     3. Scheduling: date_start, date_end, year, round, is_cancelled.
--     4. Pirelli Compound Nominations: c_hard, c_medium, c_soft (C1 to C6).
--        Translates nominal compound labels into actual rubber compound hardness.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - Natural key session_key is 100% unique (0 duplicate key groups).
--   - c_hard, c_medium, and c_soft are 100% NULL (210 empty cells = 70 * 3)
--     in raw data; mapped to official Pirelli designations in Silver.
--   - Mixed timestamp formatting: date_start is formatted without timezone offset
--     (YYYY-MM-DD HH:MM:SS) while date_end has ISO-8601 offset (+00:00).
--     Both represent UTC timestamps and are standardized in Silver.
--
-- Execution:
--   Run after Mohamed's and Yousef's bronze scripts:
--   psql -d f1_warehouse -f sql/01_bronze/03_mahmud_bronze_weather_races.sql
-- ===========================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.6: DDL Staging Tables
-- ---------------------------------------------------------------------------

-- Table: bronze.raw_weather
-- Description: Raw staging table for Weather.csv (34,420 rows).
DROP TABLE IF EXISTS bronze.raw_weather;
CREATE TABLE bronze.raw_weather (
    -- Session & Calendar Hierarchy
    year               TEXT,  -- Championship season (2023, 2024, 2025)
    round              TEXT,  -- Round number in championship
    meeting_key        TEXT,  -- Unique meeting key
    meeting_name       TEXT,  -- Grand Prix meeting name
    session_key        TEXT,  -- Unique session key (Race, Practice, Qualifying)
    session_name       TEXT,  -- Session name ('Race', 'Practice 1', 'Qualifying', etc.)
    circuit_short_name TEXT,  -- Short circuit identifier
    country_name       TEXT,  -- Host country
    -- Meteorological Telemetry
    date               TEXT,  -- UTC timestamp of weather reading
    track_temperature  TEXT,  -- Track surface temperature in degrees Celsius
    wind_speed         TEXT,  -- Wind velocity in meters per second (m/s)
    rainfall           TEXT,  -- Rain sensor detection flag (0 = Dry, 1 = Rain)
    humidity           TEXT,  -- Relative air humidity percentage (%)
    air_temperature    TEXT,  -- Ambient air temperature in degrees Celsius
    pressure           TEXT,  -- Atmospheric barometric pressure in mbar
    wind_direction     TEXT,  -- Wind compass direction in degrees (0-360)
    -- Medallion Audit Lineage Columns
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Weather.csv'
);

-- Table: bronze.raw_races
-- Description: Raw staging table for Races.csv (70 rows).
DROP TABLE IF EXISTS bronze.raw_races;
CREATE TABLE bronze.raw_races (
    -- Primary Session & Meeting Keys
    session_key            TEXT,  -- Primary unique key for race session
    session_type           TEXT,  -- Session type ('Race')
    session_name           TEXT,  -- Session name ('Race')
    -- Scheduled Timestamps
    date_start             TEXT,  -- UTC start time (YYYY-MM-DD HH:MM:SS)
    date_end               TEXT,  -- UTC end time (ISO-8601 with +00:00)
    meeting_key            TEXT,  -- Grand Prix meeting identifier
    circuit_key            TEXT,  -- Official FIA circuit identifier
    circuit_short_name     TEXT,  -- Circuit location identifier (e.g., Sakhir, Monaco)
    country_key            TEXT,  -- Country numeric identifier
    country_code           TEXT,  -- Country three-letter alpha code (e.g., BRN, ITA)
    country_name           TEXT,  -- Host country name
    location               TEXT,  -- Host city or region
    gmt_offset             TEXT,  -- Local time difference relative to UTC (e.g., 03:00:00)
    year                   TEXT,  -- Championship season (2023, 2024, 2025)
    is_cancelled           TEXT,  -- Boolean string: True if race was cancelled
    meeting_name           TEXT,  -- Popular Grand Prix name
    meeting_official_name  TEXT,  -- Full commercial official event title
    circuit_type           TEXT,  -- Track archetype: 'Permanent' vs 'Temporary - Street'
    round                  TEXT,  -- Season calendar round number
    -- Pirelli Tyre Compound Allocations (C1 = Hardest, C6 = Softest)
    c_hard                 TEXT,  -- Designated Hard tyre compound code (raw NULL)
    c_medium               TEXT,  -- Designated Medium tyre compound code (raw NULL)
    c_soft                 TEXT,  -- Designated Soft tyre compound code (raw NULL)
    -- Medallion Audit Lineage Columns
    _ingested_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file           TEXT      NOT NULL DEFAULT 'Races.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.6: Bulk Load Staging Tables
-- Blank CSV fields become NULL. Source text is otherwise strictly preserved.
-- ---------------------------------------------------------------------------

\copy bronze.raw_weather (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, track_temperature, wind_speed, rainfall, humidity, air_temperature, pressure, wind_direction) FROM '/home/mohamed/F1/raw_data/Weather.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_races (session_key, session_type, session_name, date_start, date_end, meeting_key, circuit_key, circuit_short_name, country_key, country_code, country_name, location, gmt_offset, year, is_cancelled, meeting_name, meeting_official_name, circuit_type, round, c_hard, c_medium, c_soft) FROM '/home/mohamed/F1/raw_data/Races.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.7: Diagnostics & Data Profiling
-- ---------------------------------------------------------------------------

-- Weather observations and distinct sessions per season
SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_weather
GROUP BY year
ORDER BY year;

-- Session breakdown in raw_weather: Bronze keeps all; Silver filters for Race only
SELECT COALESCE(NULLIF(BTRIM(session_name), ''), '(blank)') AS session_name, COUNT(*) AS row_count
FROM bronze.raw_weather
GROUP BY 1
ORDER BY row_count DESC;

-- Races data profiling: checking ISO-8601 vs space-separated formats and missing Pirelli compounds
-- Expected: c_hard, c_medium, c_soft are missing on all 70 race rows (210 missing cells).
SELECT
    COUNT(*) AS race_rows,
    COUNT(*) FILTER (WHERE date_start LIKE '%T%') AS date_start_iso8601,
    COUNT(*) FILTER (WHERE date_start NOT LIKE '%T%') AS date_start_space_separated,
    COUNT(*) FILTER (WHERE date_start LIKE '%+%' OR date_start LIKE '%Z') AS date_start_with_offset,
    COUNT(*) FILTER (WHERE date_end LIKE '%T%') AS date_end_iso8601,
    COUNT(*) FILTER (WHERE date_end LIKE '%+%' OR date_end LIKE '%Z') AS date_end_with_offset,
    COUNT(*) FILTER (WHERE c_hard IS NULL OR BTRIM(c_hard) = '') AS c_hard_missing,
    COUNT(*) FILTER (WHERE c_medium IS NULL OR BTRIM(c_medium) = '') AS c_medium_missing,
    COUNT(*) FILTER (WHERE c_soft IS NULL OR BTRIM(c_soft) = '') AS c_soft_missing
FROM bronze.raw_races;

-- Duplicate weather timestamp check on (session_key, date). Expected: 28 duplicate rows.
SELECT
    session_key,
    date,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_weather
GROUP BY session_key, date
HAVING COUNT(*) > 1
ORDER BY duplicate_rows DESC
LIMIT 20;
