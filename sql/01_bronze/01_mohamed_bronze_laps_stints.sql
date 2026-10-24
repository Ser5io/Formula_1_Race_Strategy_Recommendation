-- Mohamed | Phase 1 Bronze | Core lap telemetry and stint staging
-- Tasks 1.1, 1.2, 1.3
-- Pure SQL. Every source column is TEXT so the load does not truncate or cast.
-- Run with:
--   psql -d f1_warehouse -f sql/01_bronze/01_mohamed_bronze_laps_stints.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

-- Views that read these tables are dropped first so the script can be rerun.
DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.1  DDL
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.raw_race_laps;
CREATE TABLE bronze.raw_race_laps (
    year                      TEXT,
    round                     TEXT,
    meeting_key               TEXT,
    meeting_name              TEXT,
    session_key               TEXT,
    session_name              TEXT,
    circuit_short_name        TEXT,
    country_name              TEXT,
    date_start                TEXT,
    driver_number             TEXT,
    lap_number                TEXT,
    lap_duration              TEXT,
    duration_sector_1         TEXT,
    duration_sector_2         TEXT,
    duration_sector_3         TEXT,
    i1_speed                  TEXT,
    i2_speed                  TEXT,
    st_speed                  TEXT,
    is_pit_out_lap            TEXT,
    date_end                  TEXT,
    name_acronym              TEXT,
    full_name                 TEXT,
    team_name                 TEXT,
    stint_number              TEXT,
    compound                  TEXT,
    tyre_age_at_start         TEXT,
    stint_lap_start           TEXT,
    stint_lap_end             TEXT,
    compound_code             TEXT,
    tyre_age_laps             TEXT,
    tyre_is_new               TEXT,
    pit_lane_duration_s       TEXT,
    pit_stop_duration_s       TEXT,
    is_pit_in_lap             TEXT,
    safety_car_in_lap         TEXT,
    vsc_in_lap                TEXT,
    red_flag_in_lap           TEXT,
    yellow_events_in_lap      TEXT,
    yellow_flag_in_lap        TEXT,
    race_condition            TEXT,
    weather_air_temperature   TEXT,
    weather_track_temperature TEXT,
    weather_humidity          TEXT,
    weather_pressure          TEXT,
    weather_wind_speed        TEXT,
    weather_wind_direction    TEXT,
    weather_rainfall          TEXT,
    rainfall_share_of_lap     TEXT,
    position_end_of_lap       TEXT,
    lap_is_clean              TEXT,
    fuel_corrected_lap_time   TEXT,
    deg_vs_stint_best_s       TEXT,
    stint_deg_slope_s_per_lap TEXT,
    is_first_lap              TEXT,
    _ingested_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file              TEXT      NOT NULL DEFAULT 'Race_Laps.csv'
);

DROP TABLE IF EXISTS bronze.raw_stint_summary;
CREATE TABLE bronze.raw_stint_summary (
    year                              TEXT,
    round                             TEXT,
    meeting_key                       TEXT,
    meeting_name                      TEXT,
    session_key                       TEXT,
    session_name                      TEXT,
    circuit_short_name                TEXT,
    country_name                      TEXT,
    driver_number                     TEXT,
    name_acronym                      TEXT,
    team_name                         TEXT,
    stint_number                      TEXT,
    compound                          TEXT,
    compound_code                     TEXT,
    lap_start                         TEXT,
    lap_end                           TEXT,
    laps                              TEXT,
    tyre_age_at_start                 TEXT,
    tyre_is_new                       TEXT,
    clean_laps                        TEXT,
    avg_clean_lap_s                   TEXT,
    best_lap_s                        TEXT,
    deg_slope_raw_s_per_lap           TEXT,
    deg_slope_fuel_corrected_s_per_lap TEXT,
    _ingested_at                      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file                      TEXT      NOT NULL DEFAULT 'Stint_Summary.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.2  Load
-- Blank CSV fields become NULL. Source text is otherwise unchanged.
-- \copy is the client-side load, so the database user does not need
-- server file permission. The COPY statements below are the server-side
-- equivalent when the database host can read the same paths.
-- ---------------------------------------------------------------------------

\copy bronze.raw_race_laps (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date_start, driver_number, lap_number, lap_duration, duration_sector_1, duration_sector_2, duration_sector_3, i1_speed, i2_speed, st_speed, is_pit_out_lap, date_end, name_acronym, full_name, team_name, stint_number, compound, tyre_age_at_start, stint_lap_start, stint_lap_end, compound_code, tyre_age_laps, tyre_is_new, pit_lane_duration_s, pit_stop_duration_s, is_pit_in_lap, safety_car_in_lap, vsc_in_lap, red_flag_in_lap, yellow_events_in_lap, yellow_flag_in_lap, race_condition, weather_air_temperature, weather_track_temperature, weather_humidity, weather_pressure, weather_wind_speed, weather_wind_direction, weather_rainfall, rainfall_share_of_lap, position_end_of_lap, lap_is_clean, fuel_corrected_lap_time, deg_vs_stint_best_s, stint_deg_slope_s_per_lap, is_first_lap) FROM '/home/mohamed/F1/raw_data/Race_Laps.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_stint_summary (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, driver_number, name_acronym, team_name, stint_number, compound, compound_code, lap_start, lap_end, laps, tyre_age_at_start, tyre_is_new, clean_laps, avg_clean_lap_s, best_lap_s, deg_slope_raw_s_per_lap, deg_slope_fuel_corrected_s_per_lap) FROM '/home/mohamed/F1/raw_data/Stint_Summary.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- COPY bronze.raw_race_laps (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, date_start, driver_number, lap_number, lap_duration, duration_sector_1, duration_sector_2, duration_sector_3, i1_speed, i2_speed, st_speed, is_pit_out_lap, date_end, name_acronym, full_name, team_name, stint_number, compound, tyre_age_at_start, stint_lap_start, stint_lap_end, compound_code, tyre_age_laps, tyre_is_new, pit_lane_duration_s, pit_stop_duration_s, is_pit_in_lap, safety_car_in_lap, vsc_in_lap, red_flag_in_lap, yellow_events_in_lap, yellow_flag_in_lap, race_condition, weather_air_temperature, weather_track_temperature, weather_humidity, weather_pressure, weather_wind_speed, weather_wind_direction, weather_rainfall, rainfall_share_of_lap, position_end_of_lap, lap_is_clean, fuel_corrected_lap_time, deg_vs_stint_best_s, stint_deg_slope_s_per_lap, is_first_lap)
-- FROM '/home/mohamed/F1/raw_data/Race_Laps.csv' WITH (FORMAT csv, HEADER true, NULL '');
--
-- COPY bronze.raw_stint_summary (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, driver_number, name_acronym, team_name, stint_number, compound, compound_code, lap_start, lap_end, laps, tyre_age_at_start, tyre_is_new, clean_laps, avg_clean_lap_s, best_lap_s, deg_slope_raw_s_per_lap, deg_slope_fuel_corrected_s_per_lap)
-- FROM '/home/mohamed/F1/raw_data/Stint_Summary.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- Task 1.3  Diagnostics
-- ---------------------------------------------------------------------------

-- Row count and distinct sessions per season.
SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_race_laps
GROUP BY year
ORDER BY year;

SELECT
    year,
    COUNT(*)                    AS row_count,
    COUNT(DISTINCT session_key) AS distinct_session_key
FROM bronze.raw_stint_summary
GROUP BY year
ORDER BY year;

-- NULL or blank frequency on the lap columns used downstream.
SELECT
    COUNT(*) AS row_count,
    COUNT(*) FILTER (WHERE lap_duration IS NULL OR BTRIM(lap_duration) = '')              AS lap_duration_null,
    COUNT(*) FILTER (WHERE i1_speed IS NULL OR BTRIM(i1_speed) = '')                      AS i1_speed_null,
    COUNT(*) FILTER (WHERE i2_speed IS NULL OR BTRIM(i2_speed) = '')                      AS i2_speed_null,
    COUNT(*) FILTER (WHERE st_speed IS NULL OR BTRIM(st_speed) = '')                      AS st_speed_null,
    COUNT(*) FILTER (WHERE compound_code IS NULL OR BTRIM(compound_code) = '')            AS compound_code_null,
    COUNT(*) FILTER (WHERE deg_vs_stint_best_s IS NULL OR BTRIM(deg_vs_stint_best_s) = '') AS deg_vs_stint_best_s_null
FROM bronze.raw_race_laps;

-- Stint columns that arrive empty (compound code is filled later, in silver).
SELECT
    COUNT(*) AS row_count,
    COUNT(*) FILTER (WHERE compound_code IS NULL OR BTRIM(compound_code) = '') AS compound_code_null,
    COUNT(*) FILTER (WHERE avg_clean_lap_s IS NULL OR BTRIM(avg_clean_lap_s) = '') AS avg_clean_lap_s_null,
    COUNT(*) FILTER (WHERE best_lap_s IS NULL OR BTRIM(best_lap_s) = '') AS best_lap_s_null,
    COUNT(*) FILTER (WHERE deg_slope_raw_s_per_lap IS NULL OR BTRIM(deg_slope_raw_s_per_lap) = '') AS deg_slope_raw_null,
    COUNT(*) FILTER (WHERE deg_slope_fuel_corrected_s_per_lap IS NULL OR BTRIM(deg_slope_fuel_corrected_s_per_lap) = '') AS deg_slope_fuel_corrected_null
FROM bronze.raw_stint_summary;

-- Natural-key duplicates. Expected result: zero rows.
SELECT
    session_key,
    driver_number,
    lap_number,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_race_laps
GROUP BY session_key, driver_number, lap_number
HAVING COUNT(*) > 1;

SELECT
    session_key,
    driver_number,
    stint_number,
    COUNT(*) AS duplicate_rows
FROM bronze.raw_stint_summary
GROUP BY session_key, driver_number, stint_number
HAVING COUNT(*) > 1;
