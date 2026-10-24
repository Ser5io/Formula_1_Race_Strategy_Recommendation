-- Moaz | Phase 2 Silver | Driver and constructor dimensions, stints, results, audit
-- Tasks 2.9, 2.10, 2.11
-- Pure SQL. Run last. Depends on silver.txt_*, fact_race_laps, and dim_races.
--   psql -d f1_warehouse -f sql/02_silver/04_moaz_silver_dimensions_and_audit.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;

-- ---------------------------------------------------------------------------
-- Task 2.9  Drivers and constructors
-- One row per driver per season. The kept row is the one with the most races
-- entered, which drops the duplicate caused by team_colour case (3671C6 vs
-- 3671c6) and keeps the longer stint when a driver changes team mid-season.
-- team_colour is stored in upper case. team_lineage joins Alfa Romeo to
-- Kick Sauber and AlphaTauri / RB to Racing Bulls without rewriting the
-- name the team used that season.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.dim_drivers;
CREATE TABLE silver.dim_drivers (
    driver_sk         INTEGER PRIMARY KEY,
    year              INTEGER NOT NULL,
    driver_number     INTEGER NOT NULL,
    full_name         TEXT,
    name_acronym      TEXT,
    broadcast_name    TEXT,
    team_name         TEXT,
    team_lineage      TEXT,
    team_colour       TEXT,
    races_entered     INTEGER,
    first_round       INTEGER,
    last_round        INTEGER,
    final_points      NUMERIC,
    final_position    INTEGER,
    source_row_count  INTEGER NOT NULL,
    CONSTRAINT uq_dim_drivers_season UNIQUE (year, driver_number)
);

INSERT INTO silver.dim_drivers (
    driver_sk, year, driver_number, full_name, name_acronym, broadcast_name,
    team_name, team_lineage, team_colour, races_entered, first_round, last_round,
    final_points, final_position, source_row_count
)
WITH typed AS (
    SELECT
        silver.txt_int(year) AS year,
        silver.txt_int(driver_number) AS driver_number,
        NULLIF(BTRIM(full_name), '') AS full_name,
        NULLIF(BTRIM(name_acronym), '') AS name_acronym,
        NULLIF(BTRIM(broadcast_name), '') AS broadcast_name,
        NULLIF(BTRIM(team_name), '') AS team_name,
        NULLIF(BTRIM(team_colour), '') AS team_colour,
        silver.txt_int(races_entered) AS races_entered,
        silver.txt_int(first_round) AS first_round,
        silver.txt_int(last_round) AS last_round,
        CASE
            WHEN final_points IS NULL OR BTRIM(final_points) = '' THEN NULL
            ELSE BTRIM(final_points)::NUMERIC
        END AS final_points,
        silver.txt_int(final_position) AS final_position
    FROM bronze.raw_drivers
),
ranked AS (
    SELECT
        typed.*,
        ROW_NUMBER() OVER (
            PARTITION BY year, driver_number
            ORDER BY races_entered DESC NULLS LAST, last_round DESC NULLS LAST
        ) AS keep_rank,
        COUNT(*) OVER (PARTITION BY year, driver_number) AS source_row_count
    FROM typed
),
kept AS (
    SELECT * FROM ranked WHERE keep_rank = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY year, driver_number) AS driver_sk,
    year,
    driver_number,
    full_name,
    name_acronym,
    broadcast_name,
    team_name,
    CASE team_name
        WHEN 'Alfa Romeo' THEN 'Kick Sauber'
        WHEN 'AlphaTauri' THEN 'Racing Bulls'
        WHEN 'RB' THEN 'Racing Bulls'
        ELSE team_name
    END AS team_lineage,
    UPPER(team_colour) AS team_colour,
    races_entered,
    first_round,
    last_round,
    final_points,
    final_position,
    source_row_count
FROM kept;

DROP TABLE IF EXISTS silver.dim_constructors;
CREATE TABLE silver.dim_constructors (
    constructor_sk    INTEGER PRIMARY KEY,
    year              INTEGER NOT NULL,
    team_name         TEXT NOT NULL,
    team_lineage      TEXT,
    team_colour       TEXT,
    drivers           TEXT,
    races             INTEGER,
    final_points      NUMERIC,
    final_position    INTEGER,
    CONSTRAINT uq_dim_constructors_season UNIQUE (year, team_name)
);

INSERT INTO silver.dim_constructors (
    constructor_sk, year, team_name, team_lineage, team_colour,
    drivers, races, final_points, final_position
)
WITH typed AS (
    SELECT
        silver.txt_int(year) AS year,
        NULLIF(BTRIM(team_name), '') AS team_name,
        NULLIF(BTRIM(team_colour), '') AS team_colour,
        NULLIF(BTRIM(drivers), '') AS drivers,
        silver.txt_int(races) AS races,
        CASE
            WHEN final_points IS NULL OR BTRIM(final_points) = '' THEN NULL
            ELSE BTRIM(final_points)::NUMERIC
        END AS final_points,
        silver.txt_int(final_position) AS final_position
    FROM bronze.raw_constructors
)
SELECT
    ROW_NUMBER() OVER (ORDER BY year, team_name) AS constructor_sk,
    year,
    team_name,
    CASE team_name
        WHEN 'Alfa Romeo' THEN 'Kick Sauber'
        WHEN 'AlphaTauri' THEN 'Racing Bulls'
        WHEN 'RB' THEN 'Racing Bulls'
        ELSE team_name
    END AS team_lineage,
    UPPER(team_colour) AS team_colour,
    drivers,
    races,
    final_points,
    final_position
FROM typed;

-- ---------------------------------------------------------------------------
-- Task 2.10  Results and stints
-- "+1 LAP" becomes laps_down = 1 and gap_seconds NULL.
-- A numeric gap becomes gap_seconds and laps_down = 0.
-- Stint compound_code is taken from dim_races: HARD/MEDIUM/SOFT map to the
-- Pirelli code for that race. The stint average is checked against the mean
-- fuel-corrected time of valid laps in fact_race_laps.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.fact_race_results;
CREATE TABLE silver.fact_race_results (
    year                INTEGER,
    round               INTEGER,
    meeting_key         INTEGER,
    meeting_name        TEXT,
    session_key         INTEGER NOT NULL,
    session_name        TEXT,
    circuit_short_name  TEXT,
    country_name        TEXT,
    position            INTEGER,
    driver_number       INTEGER NOT NULL,
    name_acronym        TEXT,
    full_name           TEXT,
    team_name           TEXT,
    number_of_laps      INTEGER,
    points              NUMERIC,
    dnf                 BOOLEAN,
    dns                 BOOLEAN,
    dsq                 BOOLEAN,
    duration_s          DOUBLE PRECISION,
    gap_to_leader_raw   TEXT,
    gap_seconds         NUMERIC,
    laps_down           INTEGER,
    CONSTRAINT pk_fact_race_results PRIMARY KEY (session_key, driver_number)
);

INSERT INTO silver.fact_race_results (
    year, round, meeting_key, meeting_name, session_key, session_name,
    circuit_short_name, country_name, position, driver_number, name_acronym,
    full_name, team_name, number_of_laps, points, dnf, dns, dsq, duration_s,
    gap_to_leader_raw, gap_seconds, laps_down
)
SELECT
    silver.txt_int(year),
    silver.txt_int(round),
    silver.txt_int(meeting_key),
    NULLIF(BTRIM(meeting_name), ''),
    silver.txt_int(session_key),
    NULLIF(BTRIM(session_name), ''),
    NULLIF(BTRIM(circuit_short_name), ''),
    NULLIF(BTRIM(country_name), ''),
    silver.txt_int(position),
    silver.txt_int(driver_number),
    NULLIF(BTRIM(name_acronym), ''),
    NULLIF(BTRIM(full_name), ''),
    NULLIF(BTRIM(team_name), ''),
    silver.txt_int(number_of_laps),
    CASE
        WHEN points IS NULL OR BTRIM(points) = '' THEN NULL
        ELSE BTRIM(points)::NUMERIC
    END,
    silver.txt_bool(dnf),
    silver.txt_bool(dns),
    silver.txt_bool(dsq),
    silver.txt_float(duration),
    NULLIF(BTRIM(gap_to_leader), ''),
    CASE
        WHEN gap_to_leader IS NULL OR BTRIM(gap_to_leader) = '' THEN NULL
        WHEN BTRIM(gap_to_leader) ~ '^[+-]?[0-9]+(\.[0-9]+)?$'
            THEN BTRIM(gap_to_leader)::NUMERIC
        ELSE NULL
    END,
    CASE
        WHEN gap_to_leader IS NULL OR BTRIM(gap_to_leader) = '' THEN NULL
        WHEN UPPER(BTRIM(gap_to_leader)) LIKE '%LAP%'
            THEN (regexp_match(UPPER(BTRIM(gap_to_leader)), '([0-9]+)'))[1]::INTEGER
        WHEN BTRIM(gap_to_leader) ~ '^[+-]?[0-9]+(\.[0-9]+)?$' THEN 0
        ELSE NULL
    END
FROM bronze.raw_race_results;

DROP TABLE IF EXISTS silver.fact_stint_summary;
CREATE TABLE silver.fact_stint_summary (
    year                              INTEGER,
    round                             INTEGER,
    meeting_key                       INTEGER,
    meeting_name                      TEXT,
    session_key                       INTEGER NOT NULL,
    session_name                      TEXT,
    circuit_short_name                TEXT,
    country_name                      TEXT,
    driver_number                     INTEGER NOT NULL,
    name_acronym                      TEXT,
    team_name                         TEXT,
    stint_number                      INTEGER NOT NULL,
    compound                          TEXT,
    compound_code                     TEXT,
    lap_start                         INTEGER,
    lap_end                           INTEGER,
    laps                              INTEGER,
    tyre_age_at_start                 INTEGER,
    tyre_is_new                       BOOLEAN,
    clean_laps                        INTEGER,
    avg_clean_lap_s                   DOUBLE PRECISION,
    best_lap_s                        DOUBLE PRECISION,
    deg_slope_raw_s_per_lap           DOUBLE PRECISION,
    deg_slope_fuel_corrected_s_per_lap DOUBLE PRECISION,
    avg_valid_fuel_corrected_s        DOUBLE PRECISION,
    valid_lap_count                   INTEGER,
    avg_clean_lap_delta_s             DOUBLE PRECISION,
    CONSTRAINT pk_fact_stint_summary PRIMARY KEY (session_key, driver_number, stint_number)
);

INSERT INTO silver.fact_stint_summary (
    year, round, meeting_key, meeting_name, session_key, session_name,
    circuit_short_name, country_name, driver_number, name_acronym, team_name,
    stint_number, compound, compound_code, lap_start, lap_end, laps,
    tyre_age_at_start, tyre_is_new, clean_laps, avg_clean_lap_s, best_lap_s,
    deg_slope_raw_s_per_lap, deg_slope_fuel_corrected_s_per_lap,
    avg_valid_fuel_corrected_s, valid_lap_count, avg_clean_lap_delta_s
)
WITH typed AS (
    SELECT
        silver.txt_int(s.year) AS year,
        silver.txt_int(s.round) AS round,
        silver.txt_int(s.meeting_key) AS meeting_key,
        NULLIF(BTRIM(s.meeting_name), '') AS meeting_name,
        silver.txt_int(s.session_key) AS session_key,
        NULLIF(BTRIM(s.session_name), '') AS session_name,
        NULLIF(BTRIM(s.circuit_short_name), '') AS circuit_short_name,
        NULLIF(BTRIM(s.country_name), '') AS country_name,
        silver.txt_int(s.driver_number) AS driver_number,
        NULLIF(BTRIM(s.name_acronym), '') AS name_acronym,
        NULLIF(BTRIM(s.team_name), '') AS team_name,
        silver.txt_int(s.stint_number) AS stint_number,
        NULLIF(BTRIM(s.compound), '') AS compound,
        NULLIF(BTRIM(s.compound_code), '') AS compound_code_raw,
        silver.txt_int(s.lap_start) AS lap_start,
        silver.txt_int(s.lap_end) AS lap_end,
        silver.txt_int(s.laps) AS laps,
        silver.txt_int(s.tyre_age_at_start) AS tyre_age_at_start,
        silver.txt_bool(s.tyre_is_new) AS tyre_is_new,
        silver.txt_int(s.clean_laps) AS clean_laps,
        silver.txt_float(s.avg_clean_lap_s) AS avg_clean_lap_s,
        silver.txt_float(s.best_lap_s) AS best_lap_s,
        silver.txt_float(s.deg_slope_raw_s_per_lap) AS deg_slope_raw_s_per_lap,
        silver.txt_float(s.deg_slope_fuel_corrected_s_per_lap) AS deg_slope_fuel_corrected_s_per_lap
    FROM bronze.raw_stint_summary AS s
),
lap_check AS (
    SELECT
        session_key,
        driver_number,
        stint_number,
        AVG(fuel_corrected_lap_time) FILTER (WHERE is_valid_strategy_lap) AS avg_valid_fuel_corrected_s,
        COUNT(*) FILTER (WHERE is_valid_strategy_lap)::INTEGER AS valid_lap_count
    FROM silver.fact_race_laps
    GROUP BY session_key, driver_number, stint_number
)
SELECT
    typed.year,
    typed.round,
    typed.meeting_key,
    typed.meeting_name,
    typed.session_key,
    typed.session_name,
    typed.circuit_short_name,
    typed.country_name,
    typed.driver_number,
    typed.name_acronym,
    typed.team_name,
    typed.stint_number,
    typed.compound,
    COALESCE(
        typed.compound_code_raw,
        CASE UPPER(typed.compound)
            WHEN 'HARD' THEN races.c_hard
            WHEN 'MEDIUM' THEN races.c_medium
            WHEN 'SOFT' THEN races.c_soft
            WHEN 'INTERMEDIATE' THEN 'INTERMEDIATE'
            WHEN 'WET' THEN 'WET'
            ELSE NULL
        END
    ) AS compound_code,
    typed.lap_start,
    typed.lap_end,
    typed.laps,
    typed.tyre_age_at_start,
    typed.tyre_is_new,
    typed.clean_laps,
    typed.avg_clean_lap_s,
    typed.best_lap_s,
    typed.deg_slope_raw_s_per_lap,
    typed.deg_slope_fuel_corrected_s_per_lap,
    lap_check.avg_valid_fuel_corrected_s,
    lap_check.valid_lap_count,
    typed.avg_clean_lap_s - lap_check.avg_valid_fuel_corrected_s AS avg_clean_lap_delta_s
FROM typed
LEFT JOIN silver.dim_races AS races
    ON races.session_key = typed.session_key
LEFT JOIN lap_check
    ON lap_check.session_key = typed.session_key
   AND lap_check.driver_number = typed.driver_number
   AND lap_check.stint_number = typed.stint_number;

-- ---------------------------------------------------------------------------
-- Task 2.11  Transformation audit
-- ---------------------------------------------------------------------------

CREATE VIEW silver.vw_transformation_audit_log AS
SELECT 'Mohamed'::TEXT AS team_member, 'fact_race_laps'::TEXT AS object_name,
       'bronze_rows'::TEXT AS metric,
       (SELECT COUNT(*) FROM bronze.raw_race_laps)::NUMERIC AS metric_value
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_race_laps)::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'valid_strategy_laps',
       (SELECT COUNT(*) FROM silver.fact_race_laps WHERE is_valid_strategy_lap)::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'rejected_laps',
       (SELECT COUNT(*) FROM silver.fact_race_laps WHERE NOT is_valid_strategy_lap)::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'opening_laps',
       (SELECT COUNT(*) FROM silver.fact_race_laps WHERE COALESCE(is_first_lap, FALSE))::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'pit_in_or_out_laps',
       (SELECT COUNT(*) FROM silver.fact_race_laps
        WHERE COALESCE(is_pit_in_lap, FALSE) OR COALESCE(is_pit_out_lap, FALSE))::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'neutralised_laps',
       (SELECT COUNT(*) FROM silver.fact_race_laps
        WHERE COALESCE(safety_car_in_lap, FALSE)
           OR COALESCE(vsc_in_lap, FALSE)
           OR COALESCE(red_flag_in_lap, FALSE))::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'slower_than_107_percent',
       (SELECT COUNT(*) FROM silver.fact_race_laps
        WHERE driver_median_lap_s IS NOT NULL
          AND lap_duration > 1.07 * driver_median_lap_s)::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'laps_with_imputed_speed',
       (SELECT COUNT(*) FROM silver.fact_race_laps WHERE is_speed_imputed)::NUMERIC
UNION ALL
SELECT 'Mohamed', 'fact_race_laps', 'fuel_correction_mismatches',
       (
           SELECT COUNT(*)
           FROM silver.fact_race_laps AS s
           JOIN bronze.raw_race_laps AS b
             ON s.session_key = silver.txt_int(b.session_key)
            AND s.driver_number = silver.txt_int(b.driver_number)
            AND s.lap_number = silver.txt_int(b.lap_number)
           WHERE silver.txt_float(b.fuel_corrected_lap_time) IS NOT NULL
             AND ABS(s.fuel_corrected_lap_time - silver.txt_float(b.fuel_corrected_lap_time)) > 0.001
       )::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_pit_stops', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_pit_stops)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_pit_stops', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_pit_stops)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_pit_stops', 'red_flag_holds_removed',
       (SELECT COUNT(*) FROM bronze.raw_pit_stops WHERE silver.txt_float(pit_duration) > 60.0)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_pit_stops', 'penalty_stops',
       (SELECT COUNT(*) FROM silver.fact_pit_stops WHERE is_penalty_stop)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_race_control)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_race_control)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'duplicate_rows_removed',
       (
           (SELECT COUNT(*) FROM bronze.raw_race_control)
           - (SELECT COUNT(*) FROM silver.fact_race_control)
       )::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'sc_events',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_sc_event)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'vsc_events',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_vsc_event)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'red_flag_events',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_red_flag_event)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'drs_changes',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_drs_change)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'track_limit_deletions',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_track_limits_deletion)::NUMERIC
UNION ALL
SELECT 'Yousef', 'fact_race_control', 'steward_penalties',
       (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_steward_penalty)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'dim_races', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_races)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'dim_races', 'silver_rows',
       (SELECT COUNT(*) FROM silver.dim_races)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'dim_races', 'compounds_mapped',
       (SELECT COUNT(*) FROM silver.dim_races
        WHERE c_hard IS NOT NULL AND c_medium IS NOT NULL AND c_soft IS NOT NULL)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'fact_weather', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_weather)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'fact_weather', 'non_race_rows_excluded',
       (SELECT COUNT(*) FROM bronze.raw_weather WHERE BTRIM(session_name) IS DISTINCT FROM 'Race')::NUMERIC
UNION ALL
SELECT 'Mahmud', 'fact_weather', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_weather)::NUMERIC
UNION ALL
SELECT 'Mahmud', 'fact_weather', 'duplicate_race_rows_removed',
       (
           (SELECT COUNT(*) FROM bronze.raw_weather WHERE BTRIM(session_name) = 'Race')
           - (SELECT COUNT(*) FROM silver.fact_weather)
       )::NUMERIC
UNION ALL
SELECT 'Mahmud', 'fact_weather', 'rain_onset_rows',
       (SELECT COUNT(*) FROM silver.fact_weather WHERE is_rain_onset)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_drivers', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_drivers)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_drivers', 'silver_rows',
       (SELECT COUNT(*) FROM silver.dim_drivers)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_drivers', 'rows_removed_as_duplicates',
       (
           (SELECT COUNT(*) FROM bronze.raw_drivers)
           - (SELECT COUNT(*) FROM silver.dim_drivers)
       )::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_drivers', 'hex_case_values_normalised',
       (
           SELECT COUNT(*)
           FROM bronze.raw_drivers
           WHERE team_colour IS NOT NULL
             AND BTRIM(team_colour) <> UPPER(BTRIM(team_colour))
       )::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_drivers', 'lineage_names_resolved',
       (SELECT COUNT(*) FROM silver.dim_drivers WHERE team_name IS DISTINCT FROM team_lineage)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_constructors', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_constructors)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_constructors', 'silver_rows',
       (SELECT COUNT(*) FROM silver.dim_constructors)::NUMERIC
UNION ALL
SELECT 'Moaz', 'dim_constructors', 'lineage_names_resolved',
       (SELECT COUNT(*) FROM silver.dim_constructors WHERE team_name IS DISTINCT FROM team_lineage)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_race_results', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_race_results)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_race_results', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_race_results)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_race_results', 'numeric_gaps',
       (SELECT COUNT(*) FROM silver.fact_race_results WHERE gap_seconds IS NOT NULL)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_race_results', 'lapped_finishers',
       (SELECT COUNT(*) FROM silver.fact_race_results WHERE laps_down > 0)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_stint_summary', 'bronze_rows',
       (SELECT COUNT(*) FROM bronze.raw_stint_summary)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_stint_summary', 'silver_rows',
       (SELECT COUNT(*) FROM silver.fact_stint_summary)::NUMERIC
UNION ALL
SELECT 'Moaz', 'fact_stint_summary', 'compound_codes_filled',
       (SELECT COUNT(*) FROM silver.fact_stint_summary WHERE compound_code IS NOT NULL)::NUMERIC;

CREATE VIEW silver.vw_silver_audit_report AS
SELECT * FROM silver.vw_transformation_audit_log;

SELECT team_member, object_name, metric, metric_value
FROM silver.vw_transformation_audit_log
ORDER BY team_member, object_name, metric;
