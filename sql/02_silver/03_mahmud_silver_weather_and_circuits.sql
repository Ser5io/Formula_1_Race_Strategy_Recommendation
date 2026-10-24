-- Mahmud | Phase 2 Silver | Circuit dimension, Pirelli C1-C6 map, race weather
-- Tasks 2.7, 2.8
-- Pure SQL. Depends on silver.txt_* from Mohamed's silver script.
--   psql -d f1_warehouse -f sql/02_silver/03_mahmud_silver_weather_and_circuits.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;

-- ---------------------------------------------------------------------------
-- Task 2.7  Races and circuits
-- date_start is "YYYY-MM-DD HH:MM:SS" and date_end is "YYYY-MM-DDTHH:MM:SS+00:00".
-- Both clocks are UTC. date_end is converted from timestamptz to a UTC timestamp.
-- C_hard, C_medium and C_soft are empty in the extract. The lookup below is the
-- Pirelli slick nomination for that round (hard, medium, soft), including C6
-- where it was used in 2025. A source value wins if one is ever loaded.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.dim_races;
CREATE TABLE silver.dim_races (
    session_key            INTEGER PRIMARY KEY,
    session_type           TEXT,
    session_name           TEXT,
    date_start_utc         TIMESTAMP,
    date_end_utc           TIMESTAMP,
    meeting_key            INTEGER,
    circuit_key            INTEGER,
    circuit_short_name     TEXT,
    country_key            INTEGER,
    country_code           TEXT,
    country_name           TEXT,
    location               TEXT,
    gmt_offset             INTERVAL,
    year                   INTEGER,
    round                  INTEGER,
    is_cancelled           BOOLEAN,
    meeting_name           TEXT,
    meeting_official_name  TEXT,
    circuit_type           TEXT,
    c_hard                 TEXT,
    c_medium               TEXT,
    c_soft                 TEXT
);

INSERT INTO silver.dim_races (
    session_key, session_type, session_name, date_start_utc, date_end_utc,
    meeting_key, circuit_key, circuit_short_name, country_key, country_code,
    country_name, location, gmt_offset, year, round, is_cancelled,
    meeting_name, meeting_official_name, circuit_type, c_hard, c_medium, c_soft
)
WITH nomination (year, circuit_short_name, c_hard, c_medium, c_soft) AS (
    VALUES
        (2023, 'Sakhir', 'C1', 'C2', 'C3'),
        (2023, 'Jeddah', 'C2', 'C3', 'C4'),
        (2023, 'Melbourne', 'C2', 'C3', 'C4'),
        (2023, 'Baku', 'C3', 'C4', 'C5'),
        (2023, 'Miami', 'C2', 'C3', 'C4'),
        (2023, 'Monte Carlo', 'C3', 'C4', 'C5'),
        (2023, 'Catalunya', 'C1', 'C2', 'C3'),
        (2023, 'Montreal', 'C3', 'C4', 'C5'),
        (2023, 'Spielberg', 'C3', 'C4', 'C5'),
        (2023, 'Silverstone', 'C1', 'C2', 'C3'),
        (2023, 'Hungaroring', 'C3', 'C4', 'C5'),
        (2023, 'Spa-Francorchamps', 'C2', 'C3', 'C4'),
        (2023, 'Zandvoort', 'C1', 'C2', 'C3'),
        (2023, 'Monza', 'C3', 'C4', 'C5'),
        (2023, 'Singapore', 'C3', 'C4', 'C5'),
        (2023, 'Suzuka', 'C1', 'C2', 'C3'),
        (2023, 'Lusail', 'C1', 'C2', 'C3'),
        (2023, 'Austin', 'C2', 'C3', 'C4'),
        (2023, 'Mexico City', 'C3', 'C4', 'C5'),
        (2023, 'Interlagos', 'C2', 'C3', 'C4'),
        (2023, 'Las Vegas', 'C3', 'C4', 'C5'),
        (2023, 'Yas Marina Circuit', 'C3', 'C4', 'C5'),
        (2024, 'Sakhir', 'C1', 'C2', 'C3'),
        (2024, 'Jeddah', 'C2', 'C3', 'C4'),
        (2024, 'Melbourne', 'C3', 'C4', 'C5'),
        (2024, 'Suzuka', 'C1', 'C2', 'C3'),
        (2024, 'Shanghai', 'C2', 'C3', 'C4'),
        (2024, 'Miami', 'C2', 'C3', 'C4'),
        (2024, 'Imola', 'C3', 'C4', 'C5'),
        (2024, 'Monte Carlo', 'C3', 'C4', 'C5'),
        (2024, 'Montreal', 'C3', 'C4', 'C5'),
        (2024, 'Catalunya', 'C1', 'C2', 'C3'),
        (2024, 'Spielberg', 'C3', 'C4', 'C5'),
        (2024, 'Silverstone', 'C1', 'C2', 'C3'),
        (2024, 'Hungaroring', 'C3', 'C4', 'C5'),
        (2024, 'Spa-Francorchamps', 'C2', 'C3', 'C4'),
        (2024, 'Zandvoort', 'C1', 'C2', 'C3'),
        (2024, 'Monza', 'C3', 'C4', 'C5'),
        (2024, 'Baku', 'C3', 'C4', 'C5'),
        (2024, 'Singapore', 'C3', 'C4', 'C5'),
        (2024, 'Austin', 'C2', 'C3', 'C4'),
        (2024, 'Mexico City', 'C3', 'C4', 'C5'),
        (2024, 'Interlagos', 'C3', 'C4', 'C5'),
        (2024, 'Las Vegas', 'C3', 'C4', 'C5'),
        (2024, 'Lusail', 'C1', 'C2', 'C3'),
        (2024, 'Yas Marina Circuit', 'C3', 'C4', 'C5'),
        (2025, 'Melbourne', 'C3', 'C4', 'C5'),
        (2025, 'Shanghai', 'C2', 'C3', 'C4'),
        (2025, 'Suzuka', 'C1', 'C2', 'C3'),
        (2025, 'Sakhir', 'C1', 'C2', 'C3'),
        (2025, 'Jeddah', 'C3', 'C4', 'C5'),
        (2025, 'Miami', 'C3', 'C4', 'C5'),
        (2025, 'Imola', 'C4', 'C5', 'C6'),
        (2025, 'Monte Carlo', 'C4', 'C5', 'C6'),
        (2025, 'Catalunya', 'C1', 'C2', 'C3'),
        (2025, 'Montreal', 'C4', 'C5', 'C6'),
        (2025, 'Spielberg', 'C3', 'C4', 'C5'),
        (2025, 'Silverstone', 'C2', 'C3', 'C4'),
        (2025, 'Spa-Francorchamps', 'C1', 'C3', 'C4'),
        (2025, 'Hungaroring', 'C3', 'C4', 'C5'),
        (2025, 'Zandvoort', 'C2', 'C3', 'C4'),
        (2025, 'Monza', 'C3', 'C4', 'C5'),
        (2025, 'Baku', 'C4', 'C5', 'C6'),
        (2025, 'Singapore', 'C3', 'C4', 'C5'),
        (2025, 'Austin', 'C1', 'C3', 'C4'),
        (2025, 'Mexico City', 'C2', 'C4', 'C5'),
        (2025, 'Interlagos', 'C2', 'C3', 'C4'),
        (2025, 'Las Vegas', 'C3', 'C4', 'C5'),
        (2025, 'Lusail', 'C1', 'C2', 'C3'),
        (2025, 'Yas Marina Circuit', 'C3', 'C4', 'C5')
),
typed AS (
    SELECT
        silver.txt_int(session_key) AS session_key,
        NULLIF(BTRIM(session_type), '') AS session_type,
        NULLIF(BTRIM(session_name), '') AS session_name,
        silver.txt_ts(date_start) AS date_start_utc,
        CASE
            WHEN date_end IS NULL OR BTRIM(date_end) = '' THEN NULL
            WHEN BTRIM(date_end) ~ '(Z|[+-][0-9]{2})'
                THEN (BTRIM(date_end)::TIMESTAMPTZ AT TIME ZONE 'UTC')
            ELSE BTRIM(date_end)::TIMESTAMP
        END AS date_end_utc,
        silver.txt_int(meeting_key) AS meeting_key,
        silver.txt_int(circuit_key) AS circuit_key,
        NULLIF(BTRIM(circuit_short_name), '') AS circuit_short_name,
        silver.txt_int(country_key) AS country_key,
        NULLIF(BTRIM(country_code), '') AS country_code,
        NULLIF(BTRIM(country_name), '') AS country_name,
        NULLIF(BTRIM(location), '') AS location,
        NULLIF(BTRIM(gmt_offset), '')::INTERVAL AS gmt_offset,
        silver.txt_int(year) AS year,
        silver.txt_int(round) AS round,
        silver.txt_bool(is_cancelled) AS is_cancelled,
        NULLIF(BTRIM(meeting_name), '') AS meeting_name,
        NULLIF(BTRIM(meeting_official_name), '') AS meeting_official_name,
        NULLIF(BTRIM(circuit_type), '') AS circuit_type,
        NULLIF(BTRIM(c_hard), '') AS c_hard_raw,
        NULLIF(BTRIM(c_medium), '') AS c_medium_raw,
        NULLIF(BTRIM(c_soft), '') AS c_soft_raw
    FROM bronze.raw_races
)
SELECT
    typed.session_key,
    typed.session_type,
    typed.session_name,
    typed.date_start_utc,
    typed.date_end_utc,
    typed.meeting_key,
    typed.circuit_key,
    typed.circuit_short_name,
    typed.country_key,
    typed.country_code,
    typed.country_name,
    typed.location,
    typed.gmt_offset,
    typed.year,
    typed.round,
    typed.is_cancelled,
    typed.meeting_name,
    typed.meeting_official_name,
    typed.circuit_type,
    COALESCE(typed.c_hard_raw, nomination.c_hard) AS c_hard,
    COALESCE(typed.c_medium_raw, nomination.c_medium) AS c_medium,
    COALESCE(typed.c_soft_raw, nomination.c_soft) AS c_soft
FROM typed
LEFT JOIN nomination
    ON nomination.year = typed.year
   AND nomination.circuit_short_name = typed.circuit_short_name;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM silver.dim_races
        WHERE c_hard IS NULL OR c_medium IS NULL OR c_soft IS NULL
    ) THEN
        RAISE EXCEPTION 'Pirelli nomination lookup left a race without C_hard, C_medium, or C_soft';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Task 2.8  Race weather
-- Samples are one minute apart, so lag 5 is the change over the previous
-- five minutes. Non-race sessions stay in bronze and are not loaded here.
-- Duplicate (session_key, timestamp) rows keep a single observation.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.fact_weather;
CREATE TABLE silver.fact_weather (
    session_key                 INTEGER NOT NULL,
    observed_at                 TIMESTAMP NOT NULL,
    year                        INTEGER,
    round                       INTEGER,
    meeting_key                 INTEGER,
    meeting_name                TEXT,
    session_name                TEXT,
    circuit_short_name          TEXT,
    country_name                TEXT,
    track_temperature           DOUBLE PRECISION,
    air_temperature             DOUBLE PRECISION,
    humidity                    DOUBLE PRECISION,
    pressure                    DOUBLE PRECISION,
    wind_speed                  DOUBLE PRECISION,
    wind_direction              DOUBLE PRECISION,
    rainfall                    DOUBLE PRECISION,
    is_raining                  BOOLEAN NOT NULL,
    track_temp_delta_prev_5min  DOUBLE PRECISION,
    rainfall_delta_prev_5min    DOUBLE PRECISION,
    is_rain_onset               BOOLEAN NOT NULL,
    CONSTRAINT pk_fact_weather PRIMARY KEY (session_key, observed_at)
);

INSERT INTO silver.fact_weather (
    session_key, observed_at, year, round, meeting_key, meeting_name,
    session_name, circuit_short_name, country_name, track_temperature,
    air_temperature, humidity, pressure, wind_speed, wind_direction,
    rainfall, is_raining, track_temp_delta_prev_5min, rainfall_delta_prev_5min,
    is_rain_onset
)
WITH typed AS (
    SELECT
        silver.txt_int(session_key) AS session_key,
        silver.txt_ts(date) AS observed_at,
        silver.txt_int(year) AS year,
        silver.txt_int(round) AS round,
        silver.txt_int(meeting_key) AS meeting_key,
        NULLIF(BTRIM(meeting_name), '') AS meeting_name,
        NULLIF(BTRIM(session_name), '') AS session_name,
        NULLIF(BTRIM(circuit_short_name), '') AS circuit_short_name,
        NULLIF(BTRIM(country_name), '') AS country_name,
        silver.txt_float(track_temperature) AS track_temperature,
        silver.txt_float(air_temperature) AS air_temperature,
        silver.txt_float(humidity) AS humidity,
        silver.txt_float(pressure) AS pressure,
        silver.txt_float(wind_speed) AS wind_speed,
        silver.txt_float(wind_direction) AS wind_direction,
        silver.txt_float(rainfall) AS rainfall
    FROM bronze.raw_weather
    WHERE BTRIM(session_name) = 'Race'
),
deduped AS (
    SELECT *
    FROM (
        SELECT
            typed.*,
            ROW_NUMBER() OVER (
                PARTITION BY session_key, observed_at
                ORDER BY track_temperature NULLS LAST
            ) AS rn
        FROM typed
    ) AS ranked
    WHERE rn = 1
)
SELECT
    session_key,
    observed_at,
    year,
    round,
    meeting_key,
    meeting_name,
    session_name,
    circuit_short_name,
    country_name,
    track_temperature,
    air_temperature,
    humidity,
    pressure,
    wind_speed,
    wind_direction,
    rainfall,
    COALESCE(rainfall > 0, FALSE) AS is_raining,
    track_temperature - LAG(track_temperature, 5) OVER (
        PARTITION BY session_key
        ORDER BY observed_at
    ) AS track_temp_delta_prev_5min,
    rainfall - LAG(rainfall, 5) OVER (
        PARTITION BY session_key
        ORDER BY observed_at
    ) AS rainfall_delta_prev_5min,
    (
        COALESCE(rainfall, 0) > 0
        AND COALESCE(
            LAG(rainfall) OVER (PARTITION BY session_key ORDER BY observed_at),
            0
        ) = 0
    ) AS is_rain_onset
FROM deduped;

CREATE INDEX ix_fact_weather_circuit
    ON silver.fact_weather (year, circuit_short_name, observed_at);

SELECT
    (SELECT COUNT(*) FROM bronze.raw_races) AS bronze_races,
    (SELECT COUNT(*) FROM silver.dim_races) AS silver_races,
    (SELECT COUNT(*) FROM silver.dim_races WHERE c_hard IS NOT NULL) AS races_with_compounds,
    (SELECT COUNT(*) FROM bronze.raw_weather) AS bronze_weather_rows,
    (SELECT COUNT(*) FROM bronze.raw_weather WHERE BTRIM(session_name) = 'Race') AS bronze_race_weather_rows,
    (SELECT COUNT(*) FROM silver.fact_weather) AS silver_weather_rows,
    (SELECT COUNT(*) FROM silver.fact_weather WHERE is_rain_onset) AS rain_onset_rows;
