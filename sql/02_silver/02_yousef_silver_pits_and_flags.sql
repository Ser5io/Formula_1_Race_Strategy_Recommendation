-- Yousef | Phase 2 Silver | Pit-stop normalisation and race-control flags
-- Tasks 2.5, 2.6
-- Pure SQL. Depends on silver.txt_* from Mohamed's silver script.
--   psql -d f1_warehouse -f sql/02_silver/02_yousef_silver_pits_and_flags.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;

-- ---------------------------------------------------------------------------
-- Task 2.5  Pit stops
-- A pit_duration above 60 seconds is a car held in the lane under red flag,
-- not a tactical stop. Those rows are left out of the fact table.
-- net_pit_loss_s is the measured lane time. circuit_avg_pit_loss_s is the
-- mean lane time for that circuit in that season, tactical stops only.
-- is_penalty_stop is a stationary time of 5 seconds or more. The stationary
-- time is missing on most 2023 stops, and those stay unmarked.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.fact_pit_stops;
CREATE TABLE silver.fact_pit_stops (
    year                    INTEGER,
    round                   INTEGER,
    meeting_key             INTEGER,
    meeting_name            TEXT,
    session_key             INTEGER NOT NULL,
    session_name            TEXT,
    circuit_short_name      TEXT,
    country_name            TEXT,
    pit_at                  TIMESTAMP,
    driver_number           INTEGER NOT NULL,
    lap_number              INTEGER NOT NULL,
    name_acronym            TEXT,
    team_name               TEXT,
    pit_duration            DOUBLE PRECISION,
    lane_duration           DOUBLE PRECISION,
    stop_duration           DOUBLE PRECISION,
    net_pit_loss_s          DOUBLE PRECISION,
    circuit_avg_pit_loss_s  DOUBLE PRECISION,
    is_penalty_stop         BOOLEAN NOT NULL,
    CONSTRAINT pk_fact_pit_stops PRIMARY KEY (session_key, driver_number, lap_number)
);

INSERT INTO silver.fact_pit_stops (
    year, round, meeting_key, meeting_name, session_key, session_name,
    circuit_short_name, country_name, pit_at, driver_number, lap_number,
    name_acronym, team_name, pit_duration, lane_duration, stop_duration,
    net_pit_loss_s, circuit_avg_pit_loss_s, is_penalty_stop
)
WITH typed AS (
    SELECT
        silver.txt_int(year) AS year,
        silver.txt_int(round) AS round,
        silver.txt_int(meeting_key) AS meeting_key,
        NULLIF(BTRIM(meeting_name), '') AS meeting_name,
        silver.txt_int(session_key) AS session_key,
        NULLIF(BTRIM(session_name), '') AS session_name,
        NULLIF(BTRIM(circuit_short_name), '') AS circuit_short_name,
        NULLIF(BTRIM(country_name), '') AS country_name,
        silver.txt_ts(date) AS pit_at,
        silver.txt_int(driver_number) AS driver_number,
        silver.txt_int(lap_number) AS lap_number,
        NULLIF(BTRIM(name_acronym), '') AS name_acronym,
        NULLIF(BTRIM(team_name), '') AS team_name,
        silver.txt_float(pit_duration) AS pit_duration,
        silver.txt_float(lane_duration) AS lane_duration,
        silver.txt_float(stop_duration) AS stop_duration
    FROM bronze.raw_pit_stops
),
tactical AS (
    SELECT *
    FROM typed
    WHERE pit_duration IS NULL OR pit_duration <= 60.0
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
    pit_at,
    driver_number,
    lap_number,
    name_acronym,
    team_name,
    pit_duration,
    lane_duration,
    stop_duration,
    lane_duration AS net_pit_loss_s,
    AVG(lane_duration) OVER (
        PARTITION BY year, circuit_short_name
    ) AS circuit_avg_pit_loss_s,
    COALESCE(stop_duration >= 5.0, FALSE) AS is_penalty_stop
FROM tactical;

CREATE INDEX ix_fact_pit_stops_circuit
    ON silver.fact_pit_stops (year, circuit_short_name);

-- ---------------------------------------------------------------------------
-- Task 2.6  Race control
-- VIRTUAL is tested before SAFETY CAR, because every VSC message also
-- contains the words SAFETY CAR. CHEQUERED FLAG contains the letters
-- RED FLAG, so a red flag is the flag column or an exact RED FLAG message.
-- Infringement and penalty notes that mention a safety car are not deployments.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS silver.fact_race_control;
CREATE TABLE silver.fact_race_control (
    race_control_sk        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year                   INTEGER,
    round                  INTEGER,
    meeting_key            INTEGER,
    meeting_name           TEXT,
    session_key            INTEGER,
    session_name           TEXT,
    circuit_short_name     TEXT,
    country_name           TEXT,
    event_at               TIMESTAMP,
    driver_number          INTEGER,
    lap_number             INTEGER,
    category               TEXT,
    flag                   TEXT,
    scope                  TEXT,
    sector                 TEXT,
    qualifying_phase       TEXT,
    message                TEXT,
    event_code             TEXT,
    is_sc_event            BOOLEAN NOT NULL,
    is_vsc_event           BOOLEAN NOT NULL,
    is_red_flag_event      BOOLEAN NOT NULL,
    is_drs_change          BOOLEAN NOT NULL,
    is_track_limits_deletion BOOLEAN NOT NULL,
    is_steward_penalty     BOOLEAN NOT NULL
);

INSERT INTO silver.fact_race_control (
    year, round, meeting_key, meeting_name, session_key, session_name,
    circuit_short_name, country_name, event_at, driver_number, lap_number,
    category, flag, scope, sector, qualifying_phase, message, event_code,
    is_sc_event, is_vsc_event, is_red_flag_event, is_drs_change,
    is_track_limits_deletion, is_steward_penalty
)
WITH typed AS (
    SELECT
        silver.txt_int(year) AS year,
        silver.txt_int(round) AS round,
        silver.txt_int(meeting_key) AS meeting_key,
        NULLIF(BTRIM(meeting_name), '') AS meeting_name,
        silver.txt_int(session_key) AS session_key,
        NULLIF(BTRIM(session_name), '') AS session_name,
        NULLIF(BTRIM(circuit_short_name), '') AS circuit_short_name,
        NULLIF(BTRIM(country_name), '') AS country_name,
        silver.txt_ts(date) AS event_at,
        silver.txt_int(driver_number) AS driver_number,
        silver.txt_int(lap_number) AS lap_number,
        NULLIF(BTRIM(category), '') AS category,
        NULLIF(BTRIM(flag), '') AS flag,
        NULLIF(BTRIM(scope), '') AS scope,
        NULLIF(BTRIM(sector), '') AS sector,
        NULLIF(BTRIM(qualifying_phase), '') AS qualifying_phase,
        NULLIF(BTRIM(message), '') AS message
    FROM bronze.raw_race_control
),
deduped AS (
    SELECT *
    FROM (
        SELECT
            typed.*,
            ROW_NUMBER() OVER (
                PARTITION BY session_key, event_at, message
                ORDER BY driver_number NULLS LAST, lap_number NULLS LAST
            ) AS rn
        FROM typed
    ) AS ranked
    WHERE rn = 1
),
flagged AS (
    SELECT
        deduped.*,
        (
            UPPER(message) LIKE '%VIRTUAL SAFETY CAR%'
            AND UPPER(message) NOT LIKE '%INFRINGEMENT%'
            AND UPPER(message) NOT LIKE '%INCIDENT%'
            AND UPPER(message) NOT LIKE '%PENALTY%'
            AND UPPER(message) NOT LIKE '%INVESTIGAT%'
            AND UPPER(message) NOT LIKE '%NOTED%'
        ) AS is_vsc_event,
        (
            UPPER(message) LIKE '%SAFETY CAR%'
            AND UPPER(message) NOT LIKE '%VIRTUAL%'
            AND UPPER(message) NOT LIKE '%INFRINGEMENT%'
            AND UPPER(message) NOT LIKE '%INCIDENT%'
            AND UPPER(message) NOT LIKE '%PENALTY%'
            AND UPPER(message) NOT LIKE '%INVESTIGAT%'
            AND UPPER(message) NOT LIKE '%NOTED%'
        ) AS is_sc_event,
        (flag = 'RED' OR UPPER(message) = 'RED FLAG') AS is_red_flag_event,
        (
            category = 'Drs'
            OR UPPER(message) LIKE 'DRS ENABLED%'
            OR UPPER(message) LIKE 'DRS DISABLED%'
        ) AS is_drs_change,
        (
            UPPER(message) LIKE '%TRACK LIMIT%'
            AND UPPER(message) LIKE '%DELETED%'
        ) AS is_track_limits_deletion,
        (UPPER(message) LIKE '%PENALTY%') AS is_steward_penalty
    FROM deduped
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
    event_at,
    driver_number,
    lap_number,
    category,
    flag,
    scope,
    sector,
    qualifying_phase,
    message,
    CASE
        WHEN UPPER(message) LIKE '%VIRTUAL SAFETY CAR DEPLOYED%' THEN 'VSC_DEPLOYED'
        WHEN UPPER(message) LIKE '%VIRTUAL SAFETY CAR ENDING%' THEN 'VSC_ENDING'
        WHEN UPPER(message) LIKE '%SAFETY CAR DEPLOYED%' THEN 'SC_DEPLOYED'
        WHEN UPPER(message) LIKE '%SAFETY CAR IN THIS LAP%' THEN 'SC_IN_THIS_LAP'
        WHEN is_red_flag_event THEN 'RED_FLAG'
        WHEN UPPER(message) LIKE 'DRS ENABLED%' THEN 'DRS_ENABLED'
        WHEN UPPER(message) LIKE 'DRS DISABLED%' THEN 'DRS_DISABLED'
        WHEN is_track_limits_deletion THEN 'TRACK_LIMIT_DELETED'
        WHEN is_steward_penalty THEN 'PENALTY_ISSUED'
        ELSE NULL
    END AS event_code,
    COALESCE(is_sc_event, FALSE),
    COALESCE(is_vsc_event, FALSE),
    COALESCE(is_red_flag_event, FALSE),
    COALESCE(is_drs_change, FALSE),
    COALESCE(is_track_limits_deletion, FALSE),
    COALESCE(is_steward_penalty, FALSE)
FROM flagged;

CREATE INDEX ix_fact_race_control_session
    ON silver.fact_race_control (session_key, event_at);

SELECT
    (SELECT COUNT(*) FROM bronze.raw_pit_stops) AS bronze_pit_rows,
    (SELECT COUNT(*) FROM silver.fact_pit_stops) AS silver_pit_rows,
    (
        SELECT COUNT(*)
        FROM bronze.raw_pit_stops
        WHERE silver.txt_float(pit_duration) > 60.0
    ) AS red_flag_holds_removed,
    (SELECT COUNT(*) FROM silver.fact_pit_stops WHERE is_penalty_stop) AS penalty_stops;

SELECT event_code, COUNT(*) AS row_count
FROM silver.fact_race_control
WHERE event_code IS NOT NULL
GROUP BY event_code
ORDER BY row_count DESC;
