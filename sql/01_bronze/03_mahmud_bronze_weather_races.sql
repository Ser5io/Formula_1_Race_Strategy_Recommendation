-- Mahmud | Phase 1 Bronze | Weather telemetry and circuit metadata staging
-- Tasks 1.6, 1.7
-- Pure SQL. Every source column is TEXT.
-- Run after Mohamed's bronze script:
--   psql -d f1_warehouse -f sql/01_bronze/03_mahmud_bronze_weather_races.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.6  DDL
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.raw_weather;
CREATE TABLE bronze.raw_weather (
    year               TEXT,
    round              TEXT,
    meeting_key        TEXT,
    meeting_name       TEXT,
    session_key        TEXT,
    session_name       TEXT,
    circuit_short_name TEXT,
    country_name       TEXT,
    date               TEXT,
    track_temperature  TEXT,
    wind_speed         TEXT,
    rainfall           TEXT,
    humidity           TEXT,
    air_temperature    TEXT,
    pressure           TEXT,
    wind_direction     TEXT,
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Weather.csv'
);

DROP TABLE IF EXISTS bronze.raw_races;
CREATE TABLE bronze.raw_races (
    session_key            TEXT,
    session_type           TEXT,
    session_name           TEXT,
    date_start             TEXT,
    date_end               TEXT,
    meeting_key            TEXT,
    circuit_key            TEXT,
    circuit_short_name     TEXT,
    country_key            TEXT,
    country_code           TEXT,
    country_name           TEXT,
    location               TEXT,
    gmt_offset             TEXT,
    year                   TEXT,
    is_cancelled           TEXT,
    meeting_name           TEXT,
    meeting_official_name  TEXT,
    circuit_type           TEXT,
    round                  TEXT,
    c_hard                 TEXT,
    c_medium               TEXT,
    c_soft                 TEXT,
    _ingested_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file           TEXT      NOT NULL DEFAULT 'Races.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.6  Load
-- ---------------------------------------------------------------------------

\copy bronze.raw_weather (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date, track_temperature, wind_speed, rainfall, humidity, air_temperature, pressure, wind_direction) FROM '/home/mohamed/F1/raw_data/Weather.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_races (session_key, session_type, session_name, date_start, date_end, meeting_key, circuit_key, circuit_short_name, country_key, country_code, country_name, location, gmt_offset, year, is_cancelled, meeting_name, meeting_official_name, circuit_type, round, c_hard, c_medium, c_soft) FROM '/home/mohamed/F1/raw_data/Races.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.7  Diagnostics
-- ---------------------------------------------------------------------------

SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_weather
GROUP BY year
ORDER BY year;

-- Practice, qualifying and sprint rows stay in bronze. Silver keeps Race only.
SELECT COALESCE(NULLIF(BTRIM(session_name), ''), '(blank)') AS session_name, COUNT(*) AS row_count
FROM bronze.raw_weather
GROUP BY 1
ORDER BY row_count DESC;

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

SELECT
    session_key,
    date,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_weather
GROUP BY session_key, date
HAVING COUNT(*) > 1
ORDER BY duplicate_rows DESC
LIMIT 20;
