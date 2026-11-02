-- ===========================================================================
-- TEAM MEMBER: Mohamed
-- PHASE 1: BRONZE LAYER (RAW INGESTION & DIAGNOSTIC AUDIT)
-- SCRIPT: 01_mohamed_bronze_laps_stints.sql
-- TASKS: 1.1 (DDL), 1.2 (Bulk Load), 1.3 (Diagnostics)
--
-- DATASET 1: Race_Laps.csv -> bronze.raw_race_laps
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Race_Laps.csv
-- Approximate Size:  ~28.7 MB
-- Total Row Count:   77,373 rows (2023: 24,479 | 2024: 26,629 | 2025: 26,265)
-- Source Columns:    54 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, driver_number, lap_number) [0 duplicates]
-- Granularity:       1 record per driver per completed/attempted race lap
--
-- Business & Strategic Purpose:
--   Core high-frequency lap telemetry capturing the physical progression of
--   every Grand Prix. Powers:
--     1. Lap duration and micro-sector split analytics (S1, S2, S3).
--     2. Intermediate and speed-trap velocity benchmarks (i1, i2, st_speed).
--     3. Tyre lifespan tracking (stint number, compound, tyre age in laps).
--     4. Track state neutralizations (Safety Car, VSC, Red Flag, Yellows).
--     5. Synchronized trackside weather samples (ambient, track temp, rain).
--     6. Fuel-corrected pace and tyre degradation modeling in Silver and Gold.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - Ingestion: Staged as 100% TEXT to guarantee lossless ingestion.
--   - lap_duration: 258 NULL/empty cells (in-laps, out-laps, sensor dropouts).
--   - Speed traps: Missing sensor traps across laps (i1: 12,294 nulls,
--     i2: 1,119 nulls, st: 6,606 nulls). Imputed in Silver using rolling median.
--   - compound_code: 73,084 NULLs in raw; enriched in Silver via Pirelli map.
--   - deg_vs_stint_best_s: 14,258 NULLs on opening/neutralized laps.
--
-- ---------------------------------------------------------------------------
-- DATASET 2: Stint_Summary.csv -> bronze.raw_stint_summary
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Stint_Summary.csv
-- Approximate Size:  ~650 KB
-- Total Row Count:   3,934 rows (2023-2025 across all Grand Prix races)
-- Source Columns:    24 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, driver_number, stint_number) [0 duplicates]
-- Granularity:       1 record per driver per tyre stint per race session
--
-- Business & Strategic Purpose:
--   Macro tyre lifecycle aggregation recording stint lengths, starting tyre
--   conditions, average clean-lap pace, and linear degradation slopes:
--     - deg_slope_raw_s_per_lap: Raw pace decay rate per lap.
--     - deg_slope_fuel_corrected_s_per_lap: True rubber degradation rate
--       isolated from vehicle fuel burn-off (~0.030-0.035 s/lap).
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - Natural key is 100% unique (0 duplicate key groups).
--   - compound_code arrives blank/null in raw data; populated in Silver.
--   - Stints truncated by early retirements or prolonged Safety Cars have NULL
--     degradation slopes due to insufficient clean-lap sample sizes (< 3 laps).
--
-- Execution:
--   psql -d f1_warehouse -f sql/01_bronze/01_mohamed_bronze_laps_stints.sql
-- ===========================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

-- Views that read these tables are dropped first so the script can be rerun.
DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.1: DDL Staging Tables
-- ---------------------------------------------------------------------------

-- Table: bronze.raw_race_laps
-- Description: Raw staging table for Race_Laps.csv (77,373 rows).
DROP TABLE IF EXISTS bronze.raw_race_laps;
CREATE TABLE bronze.raw_race_laps (
    -- Session & Calendar Hierarchy
    year                      TEXT,  -- Championship season (2023, 2024, 2025)
    round                     TEXT,  -- Official FIA round number in championship
    meeting_key               TEXT,  -- Unique identifier for the race weekend meeting
    meeting_name              TEXT,  -- Event Grand Prix name (e.g., Bahrain Grand Prix)
    session_key               TEXT,  -- Unique identifier for the specific session
    session_name              TEXT,  -- Session type (strictly 'Race')
    circuit_short_name        TEXT,  -- Short circuit identifier (e.g., Sakhir, Monza)
    country_name              TEXT,  -- Host country (e.g., Bahrain, Italy)
    -- Lap Boundaries & Identification
    date_start                TEXT,  -- UTC timestamp when the lap commenced
    driver_number             TEXT,  -- Permanent driver race number (e.g., 1, 44)
    lap_number                TEXT,  -- Lap sequence number within the race
    lap_duration              TEXT,  -- Total lap time in seconds (e.g., 99.359)
    -- Sector Times (seconds)
    duration_sector_1         TEXT,  -- Sector 1 duration in seconds
    duration_sector_2         TEXT,  -- Sector 2 duration in seconds
    duration_sector_3         TEXT,  -- Sector 3 duration in seconds
    -- Speed Trap Velocities (km/h)
    i1_speed                  TEXT,  -- Intermediate speed trap 1 velocity in km/h
    i2_speed                  TEXT,  -- Intermediate speed trap 2 velocity in km/h
    st_speed                  TEXT,  -- Main straight speed trap velocity in km/h
    -- Pit & Traversal Flags
    is_pit_out_lap            TEXT,  -- Boolean string: True if exiting pit lane
    date_end                  TEXT,  -- UTC timestamp when the lap completed
    name_acronym              TEXT,  -- Three-letter driver acronym (e.g., VER, HAM)
    full_name                 TEXT,  -- Complete driver name (e.g., Max VERSTAPPEN)
    team_name                 TEXT,  -- Constructor team name (e.g., Red Bull Racing)
    -- Tyre & Stint Progression
    stint_number              TEXT,  -- Sequential stint index for driver in this race
    compound                  TEXT,  -- Tyre compound label (SOFT, MEDIUM, HARD, etc.)
    tyre_age_at_start         TEXT,  -- Tyre laps run before this stint commenced
    stint_lap_start           TEXT,  -- First lap number of current stint
    stint_lap_end             TEXT,  -- Final lap number of current stint
    compound_code             TEXT,  -- Pirelli compound designation (C1-C6; raw NULL)
    tyre_age_laps             TEXT,  -- Cumulative tyre age at the end of this lap
    tyre_is_new               TEXT,  -- Boolean string: True if scrubbed/new set
    pit_lane_duration_s       TEXT,  -- Total time spent in pit lane this lap (seconds)
    pit_stop_duration_s       TEXT,  -- Stationary wheel change time this lap (seconds)
    is_pit_in_lap             TEXT,  -- Boolean string: True if entering pit lane
    -- Track Neutralization & Flag Status
    safety_car_in_lap         TEXT,  -- Boolean string: Full Safety Car active
    vsc_in_lap                TEXT,  -- Boolean string: Virtual Safety Car active
    red_flag_in_lap           TEXT,  -- Boolean string: Red Flag session stoppage
    yellow_events_in_lap      TEXT,  -- Count of local yellow incidents during lap
    yellow_flag_in_lap        TEXT,  -- Boolean string: Yellow flag displayed during lap
    race_condition            TEXT,  -- Overall track condition (GREEN, YELLOW, RED)
    -- Lap Micro-Climate Weather Telemetry
    weather_air_temperature   TEXT,  -- Ambient air temperature in degrees Celsius
    weather_track_temperature TEXT,  -- Track surface temperature in degrees Celsius
    weather_humidity          TEXT,  -- Relative air humidity percentage (%)
    weather_pressure          TEXT,  -- Barometric atmospheric pressure in mbar
    weather_wind_speed        TEXT,  -- Wind velocity in meters per second (m/s)
    weather_wind_direction    TEXT,  -- Wind heading in angular degrees (0-360)
    weather_rainfall          TEXT,  -- Rain sensor detection flag (0 or 1)
    rainfall_share_of_lap     TEXT,  -- Proportion of lap distance affected by rain
    -- Performance & Strategy Engineering Features
    position_end_of_lap       TEXT,  -- Running track position at finish line
    lap_is_clean              TEXT,  -- Boolean string: True if free of traffic/flags
    fuel_corrected_lap_time   TEXT,  -- Lap time adjusted for fuel mass depletion
    deg_vs_stint_best_s       TEXT,  -- Delta time compared to best lap of the stint
    stint_deg_slope_s_per_lap TEXT,  -- Fitted tyre degradation slope (seconds/lap)
    is_first_lap              TEXT,  -- Boolean string: True for race opening lap (standing start)
    -- Medallion Audit Lineage Columns
    _ingested_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file              TEXT      NOT NULL DEFAULT 'Race_Laps.csv'
);

-- Table: bronze.raw_stint_summary
-- Description: Raw staging table for Stint_Summary.csv (3,934 rows).
DROP TABLE IF EXISTS bronze.raw_stint_summary;
CREATE TABLE bronze.raw_stint_summary (
    -- Session & Calendar Hierarchy
    year                              TEXT,  -- Championship season (2023, 2024, 2025)
    round                             TEXT,  -- Round number in championship
    meeting_key                       TEXT,  -- Grand Prix meeting identifier
    meeting_name                      TEXT,  -- Grand Prix event name
    session_key                       TEXT,  -- Unique race session key
    session_name                      TEXT,  -- Session name ('Race')
    circuit_short_name                TEXT,  -- Circuit location identifier
    country_name                      TEXT,  -- Country name
    -- Competitor Identity
    driver_number                     TEXT,  -- Driver permanent racing number
    name_acronym                      TEXT,  -- Three-letter driver acronym
    team_name                         TEXT,  -- Constructor team name
    -- Stint Characteristics & Lifespan
    stint_number                      TEXT,  -- Stint index for driver in this race (1, 2, 3...)
    compound                          TEXT,  -- Nominal compound (SOFT, MEDIUM, HARD, INTERMEDIATE, WET)
    compound_code                     TEXT,  -- Pirelli compound code (C1-C6; raw NULL)
    lap_start                         TEXT,  -- Race lap number on which stint started
    lap_end                           TEXT,  -- Race lap number on which stint concluded
    laps                              TEXT,  -- Total stint length in laps
    tyre_age_at_start                 TEXT,  -- Starting tyre age in laps
    tyre_is_new                       TEXT,  -- Boolean string: True if fresh set
    -- Clean Pace & Degradation Regression Metrics
    clean_laps                        TEXT,  -- Count of undisturbed green-flag laps in stint
    avg_clean_lap_s                   TEXT,  -- Mean lap duration across clean laps (seconds)
    best_lap_s                        TEXT,  -- Fastest clean lap recorded in stint (seconds)
    deg_slope_raw_s_per_lap           TEXT,  -- Linear degradation slope (raw seconds per lap)
    deg_slope_fuel_corrected_s_per_lap TEXT,  -- Linear degradation slope (fuel-corrected s/lap)
    -- Medallion Audit Lineage Columns
    _ingested_at                      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file                      TEXT      NOT NULL DEFAULT 'Stint_Summary.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.2: Bulk Load Staging Tables
-- Blank CSV fields become NULL. Source text is otherwise strictly preserved.
-- \copy is the client-side load mechanism (no elevated DB server filesystem
-- permission required). Server-side COPY statements are provided in comments.
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
