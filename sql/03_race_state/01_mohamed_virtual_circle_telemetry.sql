-- ==============================================================================
-- MODULE: 01_mohamed_virtual_circle_telemetry.sql
-- TEAM MEMBER: Mohamed
-- PHASE: Phase 3 (Race State Timeline Replay & Simulation Engine)
-- OBJECTIVE: Construct the chronological telemetry query & view for the 
--            Virtual Track Circle and Pit-Wall Timing Tower.
-- REPOSITORY: Formula_1_Race_Strategy_Recommendation
-- CONSTRAINTS: Zero emojis. Pure SQL CTEs, window functions, and strict types.
-- ==============================================================================

-- Drop existing view if present
DROP VIEW IF EXISTS silver.vw_race_state_timeline CASCADE;

CREATE OR REPLACE VIEW silver.vw_race_state_timeline AS
WITH ranked_laps AS (
    SELECT
        l.session_key,
        l.year,
        l.round,
        l.meeting_name,
        l.circuit_short_name,
        l.country_name,
        l.driver_number,
        l.name_acronym,
        l.full_name,
        l.team_name,
        l.lap_number,
        l.date_start,
        l.date_end,
        l.lap_duration,
        COALESCE(l.duration_sector_1, l.lap_duration / 3.0) AS duration_sector_1,
        COALESCE(l.duration_sector_2, l.lap_duration / 3.0) AS duration_sector_2,
        COALESCE(l.duration_sector_3, l.lap_duration / 3.0) AS duration_sector_3,
        l.i1_speed,
        l.i2_speed,
        l.st_speed,
        l.is_speed_imputed,
        l.stint_number,
        l.compound,
        l.compound_code,
        l.tyre_age_laps,
        l.tyre_is_new,
        l.is_pit_in_lap,
        l.is_pit_out_lap,
        l.pit_lane_duration_s,
        l.pit_stop_duration_s,
        l.safety_car_in_lap,
        l.vsc_in_lap,
        l.red_flag_in_lap,
        l.yellow_flag_in_lap,
        l.race_condition,
        l.position_end_of_lap,
        l.fuel_corrected_lap_time,
        l.deg_vs_stint_best_s,
        l.stint_deg_slope_s_per_lap,
        l.is_first_lap,
        l.is_valid_strategy_lap,
        -- Cumulative race time per driver from race start (Lap 1 date_start)
        SUM(l.lap_duration) OVER (
            PARTITION BY l.session_key, l.driver_number
            ORDER BY l.lap_number
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_race_time_s,
        -- Driver team colour from dim_constructors/dim_drivers
        COALESCE(d.team_colour, c.team_colour, '3671C6') AS team_colour
    FROM silver.fact_race_laps l
    LEFT JOIN silver.dim_drivers d
        ON l.year = d.year
        AND l.driver_number = d.driver_number
    LEFT JOIN silver.dim_constructors c
        ON l.year = c.year
        AND l.team_name = c.team_name
),
leader_reference AS (
    SELECT
        session_key,
        lap_number,
        cumulative_race_time_s AS leader_cumulative_time_s,
        driver_number AS leader_driver_number,
        name_acronym AS leader_acronym
    FROM ranked_laps
    WHERE position_end_of_lap = 1
),
interpolated_state AS (
    SELECT
        r.*,
        lr.leader_driver_number,
        lr.leader_acronym,
        -- Gap to leader in seconds
        ROUND(CAST(r.cumulative_race_time_s - lr.leader_cumulative_time_s AS NUMERIC), 3) AS gap_to_leader_s,
        -- Interval to car ahead at lap finish line
        ROUND(CAST(
            r.cumulative_race_time_s - LAG(r.cumulative_race_time_s) OVER (
                PARTITION BY r.session_key, r.lap_number
                ORDER BY r.position_end_of_lap
            ) AS NUMERIC
        ), 3) AS interval_to_ahead_s,
        -- Count of pit stops completed up to this lap
        COUNT(CASE WHEN r.is_pit_in_lap = 'TRUE' OR r.is_pit_in_lap = 't' THEN 1 END) OVER (
            PARTITION BY r.session_key, r.driver_number
            ORDER BY r.lap_number
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS pit_stop_count
    FROM ranked_laps r
    LEFT JOIN leader_reference lr
        ON r.session_key = lr.session_key
        AND r.lap_number = lr.lap_number
)
SELECT * FROM interpolated_state
ORDER BY session_key, lap_number, position_end_of_lap;
