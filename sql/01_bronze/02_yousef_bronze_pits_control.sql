-- Yousef | Phase 1 Bronze | Pit stops and FIA race control staging
-- Tasks 1.4, 1.5
-- Pure SQL. Every source column is TEXT.
-- Run after Mohamed's bronze script:
--   psql -d f1_warehouse -f sql/01_bronze/02_yousef_bronze_pits_control.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.4  DDL
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.raw_pit_stops;
CREATE TABLE bronze.raw_pit_stops (
    year               TEXT,
    round              TEXT,
    meeting_key        TEXT,
    meeting_name       TEXT,
    session_key        TEXT,
    session_name       TEXT,
    circuit_short_name TEXT,
    country_name       TEXT,
    date               TEXT,
    pit_duration       TEXT,
    driver_number      TEXT,
    lap_number         TEXT,
    lane_duration      TEXT,
    stop_duration      TEXT,
    name_acronym       TEXT,
    team_name          TEXT,
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Pit_Stops.csv'
);

DROP TABLE IF EXISTS bronze.raw_race_control;
CREATE TABLE bronze.raw_race_control (
    year               TEXT,
    round              TEXT,
    meeting_key        TEXT,
    meeting_name       TEXT,
    session_key        TEXT,
    session_name       TEXT,
    circuit_short_name TEXT,
    country_name       TEXT,
    date               TEXT,
    driver_number      TEXT,
    lap_number         TEXT,
    category           TEXT,
    flag               TEXT,
    scope              TEXT,
    sector             TEXT,
    qualifying_phase   TEXT,
    message            TEXT,
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Race_Control.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.4  Load
-- ---------------------------------------------------------------------------

\copy bronze.raw_pit_stops (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, pit_duration, driver_number, lap_number, lane_duration, stop_duration, name_acronym, team_name) FROM '/home/mohamed/F1/raw_data/Pit_Stops.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_race_control (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, driver_number, lap_number, category, flag, scope, sector, qualifying_phase, message) FROM '/home/mohamed/F1/raw_data/Race_Control.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.5  Diagnostics
-- ---------------------------------------------------------------------------

SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_pit_stops
GROUP BY year
ORDER BY year;

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

SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_race_control
GROUP BY year
ORDER BY year;

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

SELECT COALESCE(NULLIF(BTRIM(category), ''), '(blank)') AS category, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

SELECT COALESCE(NULLIF(BTRIM(flag), ''), '(blank)') AS flag, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

SELECT COALESCE(NULLIF(BTRIM(scope), ''), '(blank)') AS scope, COUNT(*) AS row_count
FROM bronze.raw_race_control
GROUP BY 1
ORDER BY row_count DESC;

SELECT
    session_key,
    driver_number,
    lap_number,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_pit_stops
GROUP BY session_key, driver_number, lap_number
HAVING COUNT(*) > 1;
