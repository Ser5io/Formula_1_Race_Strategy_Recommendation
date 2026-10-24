-- Export every Bronze and Silver table, plus both audit views, to CSV.
-- Run:
--   psql -h 127.0.0.1 -p 5434 -U postgres -d f1_warehouse -f sql/03_exports/export_bronze_silver.sql

\set ON_ERROR_STOP on

-- Mohamed
\copy (SELECT * FROM bronze.raw_race_laps ORDER BY year::INT, session_key::INT, driver_number::INT, lap_number::INT) TO '/home/mohamed/F1/exports/bronze/mohamed/raw_race_laps.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM bronze.raw_stint_summary ORDER BY year::INT, session_key::INT, driver_number::INT, stint_number::NUMERIC) TO '/home/mohamed/F1/exports/bronze/mohamed/raw_stint_summary.csv' WITH (FORMAT csv, HEADER true)

-- Yousef
\copy (SELECT * FROM bronze.raw_pit_stops ORDER BY year::INT, session_key::INT, driver_number::INT, lap_number::INT) TO '/home/mohamed/F1/exports/bronze/yousef/raw_pit_stops.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM bronze.raw_race_control ORDER BY year::INT, session_key::INT, date, lap_number) TO '/home/mohamed/F1/exports/bronze/yousef/raw_race_control.csv' WITH (FORMAT csv, HEADER true)

-- Mahmud
\copy (SELECT * FROM bronze.raw_weather ORDER BY year::INT, session_key::INT, date) TO '/home/mohamed/F1/exports/bronze/mahmud/raw_weather.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM bronze.raw_races ORDER BY year::INT, round::INT) TO '/home/mohamed/F1/exports/bronze/mahmud/raw_races.csv' WITH (FORMAT csv, HEADER true)

-- Moaz
\copy (SELECT * FROM bronze.raw_drivers ORDER BY year::INT, driver_number::INT, races_entered::INT DESC) TO '/home/mohamed/F1/exports/bronze/moaz/raw_drivers.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM bronze.raw_constructors ORDER BY year::INT, team_name) TO '/home/mohamed/F1/exports/bronze/moaz/raw_constructors.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM bronze.raw_race_results ORDER BY year::INT, round::INT, position NULLS LAST, driver_number::INT) TO '/home/mohamed/F1/exports/bronze/moaz/raw_race_results.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT * FROM bronze.vw_ingestion_audit_summary ORDER BY team_member, table_name) TO '/home/mohamed/F1/exports/bronze/bronze_audit_summary.csv' WITH (FORMAT csv, HEADER true)

-- Mohamed
\copy (SELECT * FROM silver.fact_race_laps ORDER BY session_key, driver_number, lap_number) TO '/home/mohamed/F1/exports/silver/mohamed/fact_race_laps.csv' WITH (FORMAT csv, HEADER true)

-- Yousef
\copy (SELECT * FROM silver.fact_pit_stops ORDER BY session_key, driver_number, lap_number) TO '/home/mohamed/F1/exports/silver/yousef/fact_pit_stops.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM silver.fact_race_control ORDER BY session_key, event_at, race_control_sk) TO '/home/mohamed/F1/exports/silver/yousef/fact_race_control.csv' WITH (FORMAT csv, HEADER true)

-- Mahmud
\copy (SELECT * FROM silver.dim_races ORDER BY year, round) TO '/home/mohamed/F1/exports/silver/mahmud/dim_races.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM silver.fact_weather ORDER BY session_key, observed_at) TO '/home/mohamed/F1/exports/silver/mahmud/fact_weather.csv' WITH (FORMAT csv, HEADER true)

-- Moaz
\copy (SELECT * FROM silver.dim_drivers ORDER BY year, driver_number) TO '/home/mohamed/F1/exports/silver/moaz/dim_drivers.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM silver.dim_constructors ORDER BY year, team_name) TO '/home/mohamed/F1/exports/silver/moaz/dim_constructors.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM silver.fact_race_results ORDER BY year, round, position NULLS LAST, driver_number) TO '/home/mohamed/F1/exports/silver/moaz/fact_race_results.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM silver.fact_stint_summary ORDER BY session_key, driver_number, stint_number) TO '/home/mohamed/F1/exports/silver/moaz/fact_stint_summary.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT * FROM silver.vw_transformation_audit_log ORDER BY team_member, object_name, metric) TO '/home/mohamed/F1/exports/silver/silver_audit_log.csv' WITH (FORMAT csv, HEADER true)
