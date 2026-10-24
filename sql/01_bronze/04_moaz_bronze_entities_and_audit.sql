-- Moaz | Phase 1 Bronze | Drivers, constructors, race results, and the bronze audit view
-- Tasks 1.8, 1.9, 1.10
-- Pure SQL. Every source column is TEXT.
-- Run last among the bronze scripts, after Mohamed, Yousef, and Mahmud:
--   psql -d f1_warehouse -f sql/01_bronze/04_moaz_bronze_entities_and_audit.sql

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.8  DDL
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.raw_drivers;
CREATE TABLE bronze.raw_drivers (
    year            TEXT,
    driver_number   TEXT,
    full_name       TEXT,
    name_acronym    TEXT,
    broadcast_name  TEXT,
    team_name       TEXT,
    team_colour     TEXT,
    races_entered   TEXT,
    first_round     TEXT,
    last_round      TEXT,
    final_points    TEXT,
    final_position  TEXT,
    _ingested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file    TEXT      NOT NULL DEFAULT 'Drivers.csv'
);

DROP TABLE IF EXISTS bronze.raw_constructors;
CREATE TABLE bronze.raw_constructors (
    year            TEXT,
    team_name       TEXT,
    team_colour     TEXT,
    drivers         TEXT,
    races           TEXT,
    final_points    TEXT,
    final_position  TEXT,
    _ingested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file    TEXT      NOT NULL DEFAULT 'Constructors.csv'
);

DROP TABLE IF EXISTS bronze.raw_race_results;
CREATE TABLE bronze.raw_race_results (
    year               TEXT,
    round              TEXT,
    meeting_key        TEXT,
    meeting_name       TEXT,
    session_key        TEXT,
    session_name       TEXT,
    circuit_short_name TEXT,
    country_name       TEXT,
    position           TEXT,
    driver_number      TEXT,
    number_of_laps     TEXT,
    points             TEXT,
    dnf                TEXT,
    dns                TEXT,
    dsq                TEXT,
    duration           TEXT,
    gap_to_leader      TEXT,
    name_acronym       TEXT,
    full_name          TEXT,
    team_name          TEXT,
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Race_Results.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.8  Load
-- ---------------------------------------------------------------------------

\copy bronze.raw_drivers (year, driver_number, full_name, name_acronym, broadcast_name, team_name, team_colour, races_entered, first_round, last_round, final_points, final_position) FROM '/home/mohamed/F1/raw_data/Drivers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_constructors (year, team_name, team_colour, drivers, races, final_points, final_position) FROM '/home/mohamed/F1/raw_data/Constructors.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_race_results (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, position, driver_number, number_of_laps, points, dnf, dns, dsq, duration, gap_to_leader, name_acronym, full_name, team_name) FROM '/home/mohamed/F1/raw_data/Race_Results.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.9  Diagnostics
-- ---------------------------------------------------------------------------

SELECT
    year,
    COUNT(*) AS row_count,
    COUNT(DISTINCT driver_number) AS distinct_driver_number
FROM bronze.raw_drivers
GROUP BY year
ORDER BY year;

-- Same driver and season more than once: mid-season moves, or team_colour case (3671C6 vs 3671c6).
SELECT
    year,
    driver_number,
    COUNT(*) AS duplicate_rows,
    STRING_AGG(DISTINCT team_name, ' | ' ORDER BY team_name) AS team_names,
    STRING_AGG(DISTINCT team_colour, ' | ' ORDER BY team_colour) AS team_colours
FROM bronze.raw_drivers
GROUP BY year, driver_number
HAVING COUNT(*) > 1
ORDER BY year, driver_number;

SELECT
    COUNT(*) FILTER (
        WHERE gap_to_leader IS NOT NULL
          AND BTRIM(gap_to_leader) <> ''
          AND BTRIM(gap_to_leader) !~ '^[+-]?[0-9]+(\.[0-9]+)?$'
    ) AS non_numeric_gap_to_leader,
    COUNT(*) FILTER (WHERE UPPER(gap_to_leader) LIKE '%LAP%') AS lapped_gap_rows,
    COUNT(*) FILTER (WHERE position IS NULL OR BTRIM(position) = '') AS position_null,
    COUNT(*) FILTER (WHERE duration IS NULL OR BTRIM(duration) = '') AS duration_null
FROM bronze.raw_race_results;

-- ---------------------------------------------------------------------------
-- Task 1.10  One audit row per bronze table
-- ---------------------------------------------------------------------------

CREATE VIEW bronze.vw_ingestion_audit_summary AS
SELECT
    'Mohamed'::TEXT AS team_member,
    'raw_race_laps'::TEXT AS table_name,
    COUNT(*)::BIGINT AS row_count,
    (
        SELECT COUNT(*)
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze'
          AND c.table_name = 'raw_race_laps'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER AS source_column_count,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT AS null_cell_count,
    (
        SELECT COUNT(*)
        FROM (
            SELECT 1
            FROM bronze.raw_race_laps
            GROUP BY session_key, driver_number, lap_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT AS duplicate_key_groups,
    (
        SELECT COALESCE(SUM(n - 1), 0)
        FROM (
            SELECT COUNT(*) AS n
            FROM bronze.raw_race_laps
            GROUP BY session_key, driver_number, lap_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT AS extra_duplicate_rows
FROM bronze.raw_race_laps AS src
UNION ALL
SELECT
    'Mohamed',
    'raw_stint_summary',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_stint_summary'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_stint_summary
            GROUP BY session_key, driver_number, stint_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_stint_summary
            GROUP BY session_key, driver_number, stint_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_stint_summary AS src
UNION ALL
SELECT
    'Yousef',
    'raw_pit_stops',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_pit_stops'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_pit_stops
            GROUP BY session_key, driver_number, lap_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_pit_stops
            GROUP BY session_key, driver_number, lap_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_pit_stops AS src
UNION ALL
SELECT
    'Yousef',
    'raw_race_control',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_race_control'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_race_control
            GROUP BY session_key, date, message
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_race_control
            GROUP BY session_key, date, message
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_race_control AS src
UNION ALL
SELECT
    'Mahmud',
    'raw_weather',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_weather'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_weather
            GROUP BY session_key, date
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_weather
            GROUP BY session_key, date
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_weather AS src
UNION ALL
SELECT
    'Mahmud',
    'raw_races',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_races'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_races
            GROUP BY session_key
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_races
            GROUP BY session_key
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_races AS src
UNION ALL
SELECT
    'Moaz',
    'raw_drivers',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_drivers'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_drivers
            GROUP BY year, driver_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_drivers
            GROUP BY year, driver_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_drivers AS src
UNION ALL
SELECT
    'Moaz',
    'raw_constructors',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_constructors'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_constructors
            GROUP BY year, team_name
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_constructors
            GROUP BY year, team_name
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_constructors AS src
UNION ALL
SELECT
    'Moaz',
    'raw_race_results',
    COUNT(*)::BIGINT,
    (
        SELECT COUNT(*) FROM information_schema.columns AS c
        WHERE c.table_schema = 'bronze' AND c.table_name = 'raw_race_results'
          AND c.column_name NOT IN ('_ingested_at', '_source_file')
    )::INTEGER,
    SUM((
        SELECT COUNT(*)
        FROM jsonb_each(to_jsonb(src) - '_ingested_at' - '_source_file') AS kv(key, value)
        WHERE kv.value = 'null'::JSONB
    ))::BIGINT,
    (
        SELECT COUNT(*) FROM (
            SELECT 1 FROM bronze.raw_race_results
            GROUP BY session_key, driver_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT,
    (
        SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n FROM bronze.raw_race_results
            GROUP BY session_key, driver_number
            HAVING COUNT(*) > 1
        ) AS dup
    )::BIGINT
FROM bronze.raw_race_results AS src;

CREATE VIEW bronze.vw_bronze_audit_log AS
SELECT * FROM bronze.vw_ingestion_audit_summary;

SELECT * FROM bronze.vw_ingestion_audit_summary ORDER BY team_member, table_name;
