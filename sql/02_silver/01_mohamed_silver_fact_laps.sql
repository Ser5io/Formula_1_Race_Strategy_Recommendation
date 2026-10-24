-- Mohamed | Phase 2 Silver | Lap telemetry cleaning, fuel correction, 107% rule
-- Tasks 2.1, 2.2, 2.3, 2.4
-- Pure SQL. Reads bronze.raw_race_laps only.
-- Run after sql/01_bronze/01_mohamed_bronze_laps_stints.sql:
--   psql -d f1_warehouse -f sql/02_silver/01_mohamed_silver_fact_laps.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS silver;

-- Views that read this fact table are dropped first so the script can be rerun.
DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;

-- Text from bronze is still untyped. These helpers reject blanks as NULL
-- and accept the integer-looking decimals exported by the source (for example 1.0).

CREATE OR REPLACE FUNCTION silver.txt_bool(raw TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN raw IS NULL OR BTRIM(raw) = '' THEN NULL
        WHEN LOWER(BTRIM(raw)) IN ('true', 't', '1', 'yes') THEN TRUE
        WHEN LOWER(BTRIM(raw)) IN ('false', 'f', '0', 'no') THEN FALSE
        ELSE NULL
    END;
$$;

CREATE OR REPLACE FUNCTION silver.txt_int(raw TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN raw IS NULL OR BTRIM(raw) = '' THEN NULL
        ELSE BTRIM(raw)::NUMERIC::INTEGER
    END;
$$;

CREATE OR REPLACE FUNCTION silver.txt_float(raw TEXT)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN raw IS NULL OR BTRIM(raw) = '' THEN NULL
        ELSE BTRIM(raw)::DOUBLE PRECISION
    END;
$$;

CREATE OR REPLACE FUNCTION silver.txt_ts(raw TEXT)
RETURNS TIMESTAMP
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN raw IS NULL OR BTRIM(raw) = '' THEN NULL
        ELSE BTRIM(raw)::TIMESTAMP
    END;
$$;

-- ---------------------------------------------------------------------------
-- Task 2.1  Typed fact table
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.fact_race_laps;
CREATE TABLE silver.fact_race_laps (
    year                      INTEGER,
    round                     INTEGER,
    meeting_key               INTEGER,
    meeting_name              TEXT,
    session_key               INTEGER NOT NULL,
    session_name              TEXT,
    circuit_short_name        TEXT,
    country_name              TEXT,
    date_start                TIMESTAMP,
    driver_number             INTEGER NOT NULL,
    lap_number                INTEGER NOT NULL,
    lap_duration              DOUBLE PRECISION,
    duration_sector_1         DOUBLE PRECISION,
    duration_sector_2         DOUBLE PRECISION,
    duration_sector_3         DOUBLE PRECISION,
    i1_speed                  DOUBLE PRECISION,
    i2_speed                  DOUBLE PRECISION,
    st_speed                  DOUBLE PRECISION,
    is_speed_imputed          BOOLEAN NOT NULL,
    is_pit_out_lap            BOOLEAN,
    date_end                  TIMESTAMP,
    name_acronym              TEXT,
    full_name                 TEXT,
    team_name                 TEXT,
    stint_number              INTEGER,
    compound                  TEXT,
    tyre_age_at_start         INTEGER,
    stint_lap_start           INTEGER,
    stint_lap_end             INTEGER,
    compound_code             TEXT,
    tyre_age_laps             INTEGER,
    tyre_is_new               BOOLEAN,
    pit_lane_duration_s       DOUBLE PRECISION,
    pit_stop_duration_s       DOUBLE PRECISION,
    is_pit_in_lap             BOOLEAN,
    safety_car_in_lap         BOOLEAN,
    vsc_in_lap                BOOLEAN,
    red_flag_in_lap           BOOLEAN,
    yellow_events_in_lap      INTEGER,
    yellow_flag_in_lap        BOOLEAN,
    race_condition            TEXT,
    weather_air_temperature   DOUBLE PRECISION,
    weather_track_temperature DOUBLE PRECISION,
    weather_humidity          DOUBLE PRECISION,
    weather_pressure          DOUBLE PRECISION,
    weather_wind_speed        DOUBLE PRECISION,
    weather_wind_direction    DOUBLE PRECISION,
    weather_rainfall          DOUBLE PRECISION,
    rainfall_share_of_lap     DOUBLE PRECISION,
    position_end_of_lap       INTEGER,
    lap_is_clean              BOOLEAN,
    fuel_corrected_lap_time   DOUBLE PRECISION,
    deg_vs_stint_best_s       DOUBLE PRECISION,
    stint_deg_slope_s_per_lap DOUBLE PRECISION,
    is_first_lap              BOOLEAN,
    driver_median_lap_s       DOUBLE PRECISION,
    is_valid_strategy_lap     BOOLEAN NOT NULL,
    CONSTRAINT pk_fact_race_laps PRIMARY KEY (session_key, driver_number, lap_number)
);

-- ---------------------------------------------------------------------------
-- Tasks 2.2, 2.3, 2.4  Median pace, strategy-lap flag, speed imputation,
-- fuel correction, degradation versus the best lap of the stint
-- ---------------------------------------------------------------------------
-- Fuel correction used by the source extract, confirmed on every non-null lap:
--   fuel_corrected_lap_time = lap_duration + 0.03 * (lap_number - 1)
-- The 0.03 s/lap term puts back the lap time gained as the car burns fuel.
--
-- driver_median_lap_s is the median of laps that can represent race pace.
-- Opening laps, pit in/out laps, and SC / VSC / red-flag laps are left out of
-- the median. PERCENTILE_CONT(0.5) WITHIN GROUP is grouped by session and
-- driver, then joined back: this PostgreSQL build rejects OVER on that
-- ordered-set aggregate.
--
-- is_valid_strategy_lap is FALSE for an opening lap, a pit in or pit out lap,
-- a neutralised lap (SC, VSC, or red flag), a lap with no duration, or a lap
-- slower than 107% of that driver's median. Yellow-flag laps stay eligible
-- unless they also fail the 107% test.
--
-- Missing i1_speed, i2_speed, and st_speed are filled with the driver's
-- average for that same stint. is_speed_imputed is TRUE when at least one
-- of the three values was filled. A stint with no observed speed stays NULL.

INSERT INTO silver.fact_race_laps (
    year,
    round,
    meeting_key,
    meeting_name,
    session_key,
    session_name,
    circuit_short_name,
    country_name,
    date_start,
    driver_number,
    lap_number,
    lap_duration,
    duration_sector_1,
    duration_sector_2,
    duration_sector_3,
    i1_speed,
    i2_speed,
    st_speed,
    is_speed_imputed,
    is_pit_out_lap,
    date_end,
    name_acronym,
    full_name,
    team_name,
    stint_number,
    compound,
    tyre_age_at_start,
    stint_lap_start,
    stint_lap_end,
    compound_code,
    tyre_age_laps,
    tyre_is_new,
    pit_lane_duration_s,
    pit_stop_duration_s,
    is_pit_in_lap,
    safety_car_in_lap,
    vsc_in_lap,
    red_flag_in_lap,
    yellow_events_in_lap,
    yellow_flag_in_lap,
    race_condition,
    weather_air_temperature,
    weather_track_temperature,
    weather_humidity,
    weather_pressure,
    weather_wind_speed,
    weather_wind_direction,
    weather_rainfall,
    rainfall_share_of_lap,
    position_end_of_lap,
    lap_is_clean,
    fuel_corrected_lap_time,
    deg_vs_stint_best_s,
    stint_deg_slope_s_per_lap,
    is_first_lap,
    driver_median_lap_s,
    is_valid_strategy_lap
)
WITH typed AS (
    SELECT
        silver.txt_int(year)                AS year,
        silver.txt_int(round)               AS round,
        silver.txt_int(meeting_key)         AS meeting_key,
        NULLIF(BTRIM(meeting_name), '')     AS meeting_name,
        silver.txt_int(session_key)         AS session_key,
        NULLIF(BTRIM(session_name), '')     AS session_name,
        NULLIF(BTRIM(circuit_short_name), '') AS circuit_short_name,
        NULLIF(BTRIM(country_name), '')     AS country_name,
        silver.txt_ts(date_start)           AS date_start,
        silver.txt_int(driver_number)       AS driver_number,
        silver.txt_int(lap_number)          AS lap_number,
        silver.txt_float(lap_duration)      AS lap_duration,
        silver.txt_float(duration_sector_1) AS duration_sector_1,
        silver.txt_float(duration_sector_2) AS duration_sector_2,
        silver.txt_float(duration_sector_3) AS duration_sector_3,
        silver.txt_float(i1_speed)          AS i1_speed_raw,
        silver.txt_float(i2_speed)          AS i2_speed_raw,
        silver.txt_float(st_speed)          AS st_speed_raw,
        silver.txt_bool(is_pit_out_lap)     AS is_pit_out_lap,
        silver.txt_ts(date_end)             AS date_end,
        NULLIF(BTRIM(name_acronym), '')     AS name_acronym,
        NULLIF(BTRIM(full_name), '')        AS full_name,
        NULLIF(BTRIM(team_name), '')        AS team_name,
        silver.txt_int(stint_number)        AS stint_number,
        NULLIF(BTRIM(compound), '')         AS compound,
        silver.txt_int(tyre_age_at_start)   AS tyre_age_at_start,
        silver.txt_int(stint_lap_start)     AS stint_lap_start,
        silver.txt_int(stint_lap_end)       AS stint_lap_end,
        NULLIF(BTRIM(compound_code), '')    AS compound_code,
        silver.txt_int(tyre_age_laps)       AS tyre_age_laps,
        silver.txt_bool(tyre_is_new)        AS tyre_is_new,
        silver.txt_float(pit_lane_duration_s) AS pit_lane_duration_s,
        silver.txt_float(pit_stop_duration_s) AS pit_stop_duration_s,
        silver.txt_bool(is_pit_in_lap)      AS is_pit_in_lap,
        silver.txt_bool(safety_car_in_lap)  AS safety_car_in_lap,
        silver.txt_bool(vsc_in_lap)         AS vsc_in_lap,
        silver.txt_bool(red_flag_in_lap)    AS red_flag_in_lap,
        silver.txt_int(yellow_events_in_lap) AS yellow_events_in_lap,
        silver.txt_bool(yellow_flag_in_lap) AS yellow_flag_in_lap,
        NULLIF(BTRIM(race_condition), '')   AS race_condition,
        silver.txt_float(weather_air_temperature)   AS weather_air_temperature,
        silver.txt_float(weather_track_temperature) AS weather_track_temperature,
        silver.txt_float(weather_humidity)          AS weather_humidity,
        silver.txt_float(weather_pressure)          AS weather_pressure,
        silver.txt_float(weather_wind_speed)        AS weather_wind_speed,
        silver.txt_float(weather_wind_direction)    AS weather_wind_direction,
        silver.txt_float(weather_rainfall)          AS weather_rainfall,
        silver.txt_float(rainfall_share_of_lap)     AS rainfall_share_of_lap,
        silver.txt_int(position_end_of_lap)         AS position_end_of_lap,
        silver.txt_bool(lap_is_clean)               AS lap_is_clean,
        silver.txt_float(stint_deg_slope_s_per_lap) AS stint_deg_slope_s_per_lap,
        silver.txt_bool(is_first_lap)               AS is_first_lap
    FROM bronze.raw_race_laps
),
imputed AS (
    SELECT
        typed.*,
        COALESCE(
            i1_speed_raw,
            AVG(i1_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            )
        ) AS i1_speed,
        COALESCE(
            i2_speed_raw,
            AVG(i2_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            )
        ) AS i2_speed,
        COALESCE(
            st_speed_raw,
            AVG(st_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            )
        ) AS st_speed,
        (
            (i1_speed_raw IS NULL AND AVG(i1_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            ) IS NOT NULL)
            OR
            (i2_speed_raw IS NULL AND AVG(i2_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            ) IS NOT NULL)
            OR
            (st_speed_raw IS NULL AND AVG(st_speed_raw) OVER (
                PARTITION BY session_key, driver_number, stint_number
            ) IS NOT NULL)
        ) AS is_speed_imputed,
        CASE
            WHEN lap_duration IS NULL OR lap_number IS NULL THEN NULL
            ELSE lap_duration + (0.03 * (lap_number - 1))
        END AS fuel_corrected_lap_time
    FROM typed
),
medians AS (
    SELECT
        session_key,
        driver_number,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lap_duration) AS driver_median_lap_s
    FROM imputed
    WHERE lap_duration IS NOT NULL
      AND NOT COALESCE(is_first_lap, FALSE)
      AND NOT COALESCE(is_pit_in_lap, FALSE)
      AND NOT COALESCE(is_pit_out_lap, FALSE)
      AND NOT COALESCE(safety_car_in_lap, FALSE)
      AND NOT COALESCE(vsc_in_lap, FALSE)
      AND NOT COALESCE(red_flag_in_lap, FALSE)
    GROUP BY session_key, driver_number
),
paced AS (
    SELECT
        imputed.*,
        medians.driver_median_lap_s,
        MIN(
            CASE
                WHEN imputed.fuel_corrected_lap_time IS NOT NULL
                 AND NOT COALESCE(imputed.is_first_lap, FALSE)
                 AND NOT COALESCE(imputed.is_pit_in_lap, FALSE)
                 AND NOT COALESCE(imputed.is_pit_out_lap, FALSE)
                 AND NOT COALESCE(imputed.safety_car_in_lap, FALSE)
                 AND NOT COALESCE(imputed.vsc_in_lap, FALSE)
                 AND NOT COALESCE(imputed.red_flag_in_lap, FALSE)
                THEN imputed.fuel_corrected_lap_time
            END
        ) OVER (
            PARTITION BY imputed.session_key, imputed.driver_number, imputed.stint_number
        ) AS stint_best_fuel_corrected_s
    FROM imputed
    LEFT JOIN medians
        ON medians.session_key = imputed.session_key
       AND medians.driver_number = imputed.driver_number
)
SELECT
    year,
    round,
    meeting_key,
    meeting_name,
    session_key,
    session_name,
    circuit_short_name,
    country_name,
    date_start,
    driver_number,
    lap_number,
    lap_duration,
    duration_sector_1,
    duration_sector_2,
    duration_sector_3,
    i1_speed,
    i2_speed,
    st_speed,
    COALESCE(is_speed_imputed, FALSE) AS is_speed_imputed,
    is_pit_out_lap,
    date_end,
    name_acronym,
    full_name,
    team_name,
    stint_number,
    compound,
    tyre_age_at_start,
    stint_lap_start,
    stint_lap_end,
    compound_code,
    tyre_age_laps,
    tyre_is_new,
    pit_lane_duration_s,
    pit_stop_duration_s,
    is_pit_in_lap,
    safety_car_in_lap,
    vsc_in_lap,
    red_flag_in_lap,
    yellow_events_in_lap,
    yellow_flag_in_lap,
    race_condition,
    weather_air_temperature,
    weather_track_temperature,
    weather_humidity,
    weather_pressure,
    weather_wind_speed,
    weather_wind_direction,
    weather_rainfall,
    rainfall_share_of_lap,
    position_end_of_lap,
    lap_is_clean,
    fuel_corrected_lap_time,
    CASE
        WHEN fuel_corrected_lap_time IS NULL OR stint_best_fuel_corrected_s IS NULL THEN NULL
        ELSE fuel_corrected_lap_time - stint_best_fuel_corrected_s
    END AS deg_vs_stint_best_s,
    stint_deg_slope_s_per_lap,
    is_first_lap,
    driver_median_lap_s,
    CASE
        WHEN lap_duration IS NULL THEN FALSE
        WHEN COALESCE(is_first_lap, FALSE) THEN FALSE
        WHEN COALESCE(is_pit_in_lap, FALSE) OR COALESCE(is_pit_out_lap, FALSE) THEN FALSE
        WHEN COALESCE(safety_car_in_lap, FALSE)
          OR COALESCE(vsc_in_lap, FALSE)
          OR COALESCE(red_flag_in_lap, FALSE) THEN FALSE
        WHEN driver_median_lap_s IS NOT NULL
         AND lap_duration > (1.07 * driver_median_lap_s) THEN FALSE
        ELSE TRUE
    END AS is_valid_strategy_lap
FROM paced;

CREATE INDEX ix_fact_race_laps_session_lap
    ON silver.fact_race_laps (session_key, lap_number);

CREATE INDEX ix_fact_race_laps_valid
    ON silver.fact_race_laps (session_key, driver_number)
    WHERE is_valid_strategy_lap;

-- ---------------------------------------------------------------------------
-- Mohamed | Silver checks for the transformation report
-- ---------------------------------------------------------------------------

-- Before and after.
SELECT
    (SELECT COUNT(*) FROM bronze.raw_race_laps) AS bronze_rows,
    (SELECT COUNT(*) FROM silver.fact_race_laps) AS silver_rows;

-- Why a lap was rejected. One lap can match more than one reason.
SELECT
    COUNT(*) AS silver_rows,
    COUNT(*) FILTER (WHERE is_valid_strategy_lap) AS valid_strategy_laps,
    COUNT(*) FILTER (WHERE NOT is_valid_strategy_lap) AS rejected_laps,
    COUNT(*) FILTER (WHERE lap_duration IS NULL) AS missing_lap_duration,
    COUNT(*) FILTER (WHERE COALESCE(is_first_lap, FALSE)) AS opening_laps,
    COUNT(*) FILTER (
        WHERE COALESCE(is_pit_in_lap, FALSE) OR COALESCE(is_pit_out_lap, FALSE)
    ) AS pit_in_or_out_laps,
    COUNT(*) FILTER (
        WHERE COALESCE(safety_car_in_lap, FALSE)
           OR COALESCE(vsc_in_lap, FALSE)
           OR COALESCE(red_flag_in_lap, FALSE)
    ) AS neutralised_laps,
    COUNT(*) FILTER (
        WHERE driver_median_lap_s IS NOT NULL
          AND lap_duration > (1.07 * driver_median_lap_s)
    ) AS slower_than_107_percent,
    COUNT(*) FILTER (WHERE is_speed_imputed) AS laps_with_imputed_speed
FROM silver.fact_race_laps;

-- Fuel correction must match the value stored in bronze, where bronze had one.
SELECT
    COUNT(*) FILTER (
        WHERE silver.txt_float(b.fuel_corrected_lap_time) IS NOT NULL
          AND s.fuel_corrected_lap_time IS NOT NULL
          AND ABS(
                s.fuel_corrected_lap_time
                - silver.txt_float(b.fuel_corrected_lap_time)
              ) > 0.001
    ) AS fuel_correction_mismatches
FROM silver.fact_race_laps AS s
JOIN bronze.raw_race_laps AS b
  ON s.session_key = silver.txt_int(b.session_key)
 AND s.driver_number = silver.txt_int(b.driver_number)
 AND s.lap_number = silver.txt_int(b.lap_number);
