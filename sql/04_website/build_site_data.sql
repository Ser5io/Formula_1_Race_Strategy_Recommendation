-- Build website/data/site_data.js from the bronze and silver warehouse.
--   psql -h 127.0.0.1 -p 5434 -U postgres -d f1_warehouse -f sql/04_website/build_site_data.sql

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\pset pager off
\o /home/mohamed/F1/website/data/site_data.js

SELECT 'window.F1_DATA = ' || jsonb_pretty(jsonb_build_object(
    'summary', jsonb_build_object(
        'bronze_laps', (SELECT COUNT(*) FROM bronze.raw_race_laps),
        'silver_laps', (SELECT COUNT(*) FROM silver.fact_race_laps),
        'valid_laps', (SELECT COUNT(*) FROM silver.fact_race_laps WHERE is_valid_strategy_lap),
        'rejected_laps', (SELECT COUNT(*) FROM silver.fact_race_laps WHERE NOT is_valid_strategy_lap),
        'imputed_speed_laps', (SELECT COUNT(*) FROM silver.fact_race_laps WHERE is_speed_imputed),
        'fuel_mismatches', (
            SELECT COUNT(*)
            FROM silver.fact_race_laps AS s
            JOIN bronze.raw_race_laps AS b
              ON s.session_key = silver.txt_int(b.session_key)
             AND s.driver_number = silver.txt_int(b.driver_number)
             AND s.lap_number = silver.txt_int(b.lap_number)
            WHERE silver.txt_float(b.fuel_corrected_lap_time) IS NOT NULL
              AND ABS(s.fuel_corrected_lap_time - silver.txt_float(b.fuel_corrected_lap_time)) > 0.001
        ),
        'races', (SELECT COUNT(*) FROM silver.dim_races),
        'compounds_mapped', (
            SELECT COUNT(*) FROM silver.dim_races
            WHERE c_hard IS NOT NULL AND c_medium IS NOT NULL AND c_soft IS NOT NULL
        ),
        'weather_bronze', (SELECT COUNT(*) FROM bronze.raw_weather),
        'weather_silver', (SELECT COUNT(*) FROM silver.fact_weather),
        'weather_excluded', (
            SELECT COUNT(*) FROM bronze.raw_weather
            WHERE BTRIM(session_name) IS DISTINCT FROM 'Race'
        ),
        'rain_onsets', (SELECT COUNT(*) FROM silver.fact_weather WHERE is_rain_onset),
        'pit_bronze', (SELECT COUNT(*) FROM bronze.raw_pit_stops),
        'pit_silver', (SELECT COUNT(*) FROM silver.fact_pit_stops),
        'pit_holds_removed', (
            SELECT COUNT(*) FROM bronze.raw_pit_stops
            WHERE silver.txt_float(pit_duration) > 60.0
        ),
        'penalty_stops', (SELECT COUNT(*) FROM silver.fact_pit_stops WHERE is_penalty_stop),
        'control_bronze', (SELECT COUNT(*) FROM bronze.raw_race_control),
        'control_silver', (SELECT COUNT(*) FROM silver.fact_race_control),
        'sc_events', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_sc_event),
        'vsc_events', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_vsc_event),
        'red_flag_events', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_red_flag_event),
        'drs_changes', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_drs_change),
        'track_limit_deletions', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_track_limits_deletion),
        'penalties', (SELECT COUNT(*) FROM silver.fact_race_control WHERE is_steward_penalty),
        'drivers_bronze', (SELECT COUNT(*) FROM bronze.raw_drivers),
        'drivers_silver', (SELECT COUNT(*) FROM silver.dim_drivers),
        'drivers_removed', (
            (SELECT COUNT(*) FROM bronze.raw_drivers) - (SELECT COUNT(*) FROM silver.dim_drivers)
        ),
        'hex_normalised', (
            SELECT COUNT(*) FROM bronze.raw_drivers
            WHERE team_colour IS NOT NULL
              AND BTRIM(team_colour) <> UPPER(BTRIM(team_colour))
        ),
        'stints', (SELECT COUNT(*) FROM silver.fact_stint_summary),
        'stints_with_code', (SELECT COUNT(*) FROM silver.fact_stint_summary WHERE compound_code IS NOT NULL),
        'results', (SELECT COUNT(*) FROM silver.fact_race_results),
        'lapped', (SELECT COUNT(*) FROM silver.fact_race_results WHERE laps_down > 0),
        'numeric_gaps', (SELECT COUNT(*) FROM silver.fact_race_results WHERE gap_seconds IS NOT NULL),
        'constructors', (SELECT COUNT(*) FROM silver.dim_constructors)
    ),
    'bronze_audit', (
        SELECT jsonb_agg(to_jsonb(t) ORDER BY t.team_member, t.table_name)
        FROM bronze.vw_ingestion_audit_summary AS t
    ),
    'silver_audit', (
        SELECT jsonb_agg(to_jsonb(t) ORDER BY t.team_member, t.object_name, t.metric)
        FROM silver.vw_transformation_audit_log AS t
    ),
    'laps_by_year', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.year)
        FROM (
            SELECT
                year,
                COUNT(*) AS bronze_laps,
                COUNT(*) FILTER (WHERE is_valid_strategy_lap) AS valid_laps,
                COUNT(*) FILTER (WHERE NOT is_valid_strategy_lap) AS rejected_laps
            FROM silver.fact_race_laps
            GROUP BY year
        ) AS x
    ),
    'rejection_reasons', jsonb_build_object(
        'opening', (SELECT COUNT(*) FROM silver.fact_race_laps WHERE COALESCE(is_first_lap, FALSE)),
        'pit', (
            SELECT COUNT(*) FROM silver.fact_race_laps
            WHERE COALESCE(is_pit_in_lap, FALSE) OR COALESCE(is_pit_out_lap, FALSE)
        ),
        'neutralised', (
            SELECT COUNT(*) FROM silver.fact_race_laps
            WHERE COALESCE(safety_car_in_lap, FALSE)
               OR COALESCE(vsc_in_lap, FALSE)
               OR COALESCE(red_flag_in_lap, FALSE)
        ),
        'slower_107', (
            SELECT COUNT(*) FROM silver.fact_race_laps
            WHERE driver_median_lap_s IS NOT NULL
              AND lap_duration > 1.07 * driver_median_lap_s
        ),
        'missing_duration', (
            SELECT COUNT(*) FROM silver.fact_race_laps WHERE lap_duration IS NULL
        )
    ),
    'compound_usage', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.year, x.compound)
        FROM (
            SELECT
                year,
                compound,
                COUNT(*) AS stints,
                ROUND(AVG(deg_slope_fuel_corrected_s_per_lap)::NUMERIC, 4) AS avg_deg
            FROM silver.fact_stint_summary
            WHERE compound IS NOT NULL
            GROUP BY year, compound
        ) AS x
    ),
    'pirelli_map', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.year, x.round)
        FROM (
            SELECT year, round, circuit_short_name AS circuit, meeting_name, c_hard, c_medium, c_soft
            FROM silver.dim_races
        ) AS x
    ),
    'pit_loss', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.avg_loss DESC)
        FROM (
            SELECT
                circuit_short_name AS circuit,
                COUNT(*) AS stops,
                ROUND(AVG(net_pit_loss_s)::NUMERIC, 2) AS avg_loss
            FROM silver.fact_pit_stops
            GROUP BY circuit_short_name
        ) AS x
    ),
    'flags_by_circuit', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.sc DESC)
        FROM (
            SELECT
                circuit_short_name AS circuit,
                COUNT(*) FILTER (WHERE is_sc_event) AS sc,
                COUNT(*) FILTER (WHERE is_vsc_event) AS vsc,
                COUNT(*) FILTER (WHERE is_red_flag_event) AS red
            FROM silver.fact_race_control
            GROUP BY circuit_short_name
        ) AS x
    ),
    'bahrain_temp', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.observed_at)
        FROM (
            SELECT
                to_char(observed_at, 'HH24:MI') AS observed_at,
                ROUND(track_temperature::NUMERIC, 1) AS track_temp,
                ROUND(air_temperature::NUMERIC, 1) AS air_temp,
                rainfall
            FROM silver.fact_weather
            WHERE year = 2023
              AND circuit_short_name = 'Sakhir'
        ) AS x
    ),
    'drivers_by_year', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.year)
        FROM (
            SELECT
                b.year,
                b.bronze_rows,
                COUNT(d.driver_number) AS silver_rows
            FROM (
                SELECT silver.txt_int(year) AS year, COUNT(*) AS bronze_rows
                FROM bronze.raw_drivers
                GROUP BY silver.txt_int(year)
            ) AS b
            LEFT JOIN silver.dim_drivers AS d ON d.year = b.year
            GROUP BY b.year, b.bronze_rows
        ) AS x
    ),
    'team_colours', (
        SELECT jsonb_agg(row_to_json(x) ORDER BY x.year, x.final_position)
        FROM (
            SELECT year, team_name, team_lineage, team_colour, final_position, final_points
            FROM silver.dim_constructors
        ) AS x
    ),
    'columns', (
        SELECT jsonb_agg(
            jsonb_build_object(
                'schema', c.table_schema,
                'table_name', c.table_name,
                'column_name', c.column_name,
                'data_type', c.data_type
            )
            ORDER BY c.table_schema, c.table_name, c.ordinal_position
        )
        FROM information_schema.columns AS c
        WHERE c.table_schema IN ('bronze', 'silver')
          AND c.table_name NOT LIKE 'vw_%'
    ),
    'examples', jsonb_build_object(
        'lap', (
            SELECT jsonb_build_object(
                'year', s.year,
                'circuit', s.circuit_short_name,
                'driver', s.full_name,
                'lap_number', s.lap_number,
                'bronze_lap_duration', b.lap_duration,
                'bronze_fuel', b.fuel_corrected_lap_time,
                'bronze_first', b.is_first_lap,
                'bronze_compound', b.compound,
                'silver_lap_duration', s.lap_duration,
                'silver_fuel', s.fuel_corrected_lap_time,
                'median', s.driver_median_lap_s,
                'threshold', ROUND((s.driver_median_lap_s * 1.07)::NUMERIC, 3),
                'valid', s.is_valid_strategy_lap,
                'is_first', s.is_first_lap
            )
            FROM silver.fact_race_laps AS s
            JOIN bronze.raw_race_laps AS b
              ON s.session_key = silver.txt_int(b.session_key)
             AND s.driver_number = silver.txt_int(b.driver_number)
             AND s.lap_number = silver.txt_int(b.lap_number)
            WHERE s.year = 2023
              AND s.circuit_short_name = 'Sakhir'
              AND s.driver_number = 1
              AND s.lap_number = 2
        ),
        'lap1', (
            SELECT jsonb_build_object(
                'lap_number', s.lap_number,
                'bronze_lap_duration', b.lap_duration,
                'is_first', s.is_first_lap,
                'valid', s.is_valid_strategy_lap,
                'race_condition', s.race_condition
            )
            FROM silver.fact_race_laps AS s
            JOIN bronze.raw_race_laps AS b
              ON s.session_key = silver.txt_int(b.session_key)
             AND s.driver_number = silver.txt_int(b.driver_number)
             AND s.lap_number = silver.txt_int(b.lap_number)
            WHERE s.year = 2023
              AND s.circuit_short_name = 'Sakhir'
              AND s.driver_number = 1
              AND s.lap_number = 1
        ),
        'pit_hold', (
            SELECT jsonb_build_object(
                'year', year,
                'circuit', circuit_short_name,
                'driver', name_acronym,
                'lap_number', lap_number,
                'pit_duration', pit_duration
            )
            FROM bronze.raw_pit_stops
            WHERE silver.txt_float(pit_duration) > 60
            ORDER BY silver.txt_float(pit_duration)
            LIMIT 1
        ),
        'driver_rows', (
            SELECT jsonb_build_object(
                'bronze', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'team_name', team_name,
                        'team_colour', team_colour,
                        'races_entered', races_entered
                    ) ORDER BY races_entered::INT DESC)
                    FROM bronze.raw_drivers
                    WHERE year = '2024' AND driver_number = '1'
                ),
                'silver', (
                    SELECT jsonb_build_object(
                        'team_name', team_name,
                        'team_colour', team_colour,
                        'races_entered', races_entered,
                        'source_row_count', source_row_count
                    )
                    FROM silver.dim_drivers
                    WHERE year = 2024 AND driver_number = 1
                )
            )
        ),
        'lapped', (
            SELECT jsonb_build_object(
                'year', year,
                'circuit', circuit_short_name,
                'driver', name_acronym,
                'gap_raw', gap_to_leader_raw,
                'gap_seconds', gap_seconds,
                'laps_down', laps_down
            )
            FROM silver.fact_race_results
            WHERE laps_down = 1
            ORDER BY year, round
            LIMIT 1
        ),
        'compounds', (
            SELECT jsonb_build_object(
                'circuit', r.circuit_short_name,
                'year', r.year,
                'bronze_hard', b.c_hard,
                'bronze_medium', b.c_medium,
                'bronze_soft', b.c_soft,
                'c_hard', r.c_hard,
                'c_medium', r.c_medium,
                'c_soft', r.c_soft
            )
            FROM silver.dim_races AS r
            JOIN bronze.raw_races AS b ON r.session_key = silver.txt_int(b.session_key)
            WHERE r.year = 2023 AND r.circuit_short_name = 'Sakhir'
        )
    )
)) || ';';

\o
\pset format aligned
\pset tuples_only off
