-- ===========================================================================
-- TEAM MEMBER: Moaz
-- PHASE 1: BRONZE LAYER (RAW INGESTION & DIAGNOSTIC AUDIT)
-- SCRIPT: 04_moaz_bronze_entities_and_audit.sql
-- TASKS: 1.8 (DDL & Bulk Load), 1.9 (Diagnostics), 1.10 (Master Audit Summary View)
--
-- DATASET 7: Drivers.csv -> bronze.raw_drivers
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Drivers.csv
-- Approximate Size:  ~7.7 KB
-- Total Row Count:   106 rows (2023-2025 across all active drivers)
-- Source Columns:    12 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Candidate: (year, driver_number) [34 duplicate groups; 38 extra rows]
-- Granularity:       1 record per driver per season / team tenure
--
-- Business & Strategic Purpose:
--   Master competitor dimension establishing driver identities:
--     1. Driver identifiers: driver_number (permanent FIA racing number),
--        full_name, name_acronym (three-letter code: VER, HAM, NOR, LEC).
--     2. Broadcast naming: broadcast_name for UI display and replay engine.
--     3. Team affiliation: team_name and official livery hex team_colour.
--     4. Season achievements: races_entered, first_round, last_round, final_points,
--        and championship final_position.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - 34 duplicate (year, driver_number) groups exist due to mid-season team swaps
--     (e.g., Ricciardo/Lawson/De Vries at AlphaTauri, Colapinto at Williams) and
--     inconsistent hex code casing (e.g., '3671C6' vs '3671c6').
--   - Deduplicated in Silver by selecting the latest tenure per season
--     (ORDER BY last_round DESC, final_points DESC).
--
-- ---------------------------------------------------------------------------
-- DATASET 8: Constructors.csv -> bronze.raw_constructors
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Constructors.csv
-- Approximate Size:  ~1.47 KB
-- Total Row Count:   30 rows (exactly 10 teams x 3 seasons: 2023, 2024, 2025)
-- Source Columns:    7 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (year, team_name) [0 duplicates across all seasons]
-- Granularity:       1 record per Formula 1 constructor team per championship season
--
-- Business & Strategic Purpose:
--   Master constructor dimension establishing team branding and performance:
--     1. team_name: Canonical team name matching lap and pit telemetry.
--     2. team_colour: Official brand livery hex code (without '#'), used across
--        the entire application UI (Phase 3 Replay and Phase 4 Strategist App).
--     3. Roster & performance: drivers acronym list, races, final_points, final_position.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - 0 NULL values across all 30 records.
--   - 0 duplicate keys. Highly clean reference dimension.
--
-- ---------------------------------------------------------------------------
-- DATASET 9: Race_Results.csv -> bronze.raw_race_results
-- ---------------------------------------------------------------------------
-- Source Path:       raw_data/Race_Results.csv
-- Approximate Size:  ~194 KB
-- Total Row Count:   1,397 rows (2023-2025 across all Grand Prix races)
-- Source Columns:    20 columns
-- Metadata Columns:  _ingested_at (TIMESTAMP), _source_file (TEXT)
-- Natural Key:       (session_key, driver_number) [0 duplicates; 100% unique]
-- Granularity:       1 record per driver per Grand Prix race classification
--
-- Business & Strategic Purpose:
--   Official FIA race classification and championship points scoring:
--     1. Finishing position: Official rank (1-20) or NULL if retired.
--     2. Completed race distance: number_of_laps completed by driver.
--     3. World Championship points: points scored including fastest lap bonus.
--     4. Retirement status: dnf (Did Not Finish), dns (Did Not Start), dsq (Disqualified).
--     5. Total race duration and winning margin: duration (seconds) and gap_to_leader.
--   Serves as the ground truth outcome for validating race strategy models.
--
-- Data Profiling & Quality Characteristics in Bronze:
--   - 297 rows contain non-numeric gap_to_leader strings (e.g., '+1 LAP', '+2 LAPS').
--     In Silver, parsed into numeric gap seconds and laps_behind_leader counter.
--   - 154 rows have NULL position (early retirements / DNFs).
--   - 473 rows have NULL duration (drivers who failed to complete full race distance).
--
-- Execution:
--   Run last among the bronze scripts, after Mohamed, Yousef, and Mahmud:
--   psql -d f1_warehouse -f sql/01_bronze/04_moaz_bronze_entities_and_audit.sql
-- ===========================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;

DROP VIEW IF EXISTS silver.vw_silver_audit_report;
DROP VIEW IF EXISTS silver.vw_transformation_audit_log;
DROP VIEW IF EXISTS bronze.vw_bronze_audit_log;
DROP VIEW IF EXISTS bronze.vw_ingestion_audit_summary;

-- ---------------------------------------------------------------------------
-- Task 1.8: DDL Staging Tables
-- ---------------------------------------------------------------------------

-- Table: bronze.raw_drivers
-- Description: Raw staging table for Drivers.csv (106 rows).
DROP TABLE IF EXISTS bronze.raw_drivers;
CREATE TABLE bronze.raw_drivers (
    -- Driver Profile & Team Membership
    year            TEXT,  -- Championship season (2023, 2024, 2025)
    driver_number   TEXT,  -- Permanent FIA driver number (e.g., 1, 44, 16)
    full_name       TEXT,  -- Full driver name (e.g., Max VERSTAPPEN)
    name_acronym    TEXT,  -- Three-letter driver acronym (e.g., VER, HAM, LEC)
    broadcast_name  TEXT,  -- Television broadcast display name (e.g., M VERSTAPPEN)
    team_name       TEXT,  -- Constructor team name (e.g., Red Bull Racing)
    team_colour     TEXT,  -- Hex color code without '#' (e.g., 3671C6, F91536)
    -- Participation & Championship Standings
    races_entered   TEXT,  -- Number of Grands Prix entered in the season
    first_round     TEXT,  -- Calendar round number of first entry
    last_round      TEXT,  -- Calendar round number of final entry
    final_points    TEXT,  -- Total season championship points scored
    final_position  TEXT,  -- Drivers' World Championship final finishing rank
    -- Medallion Audit Lineage Columns
    _ingested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file    TEXT      NOT NULL DEFAULT 'Drivers.csv'
);

-- Table: bronze.raw_constructors
-- Description: Raw staging table for Constructors.csv (30 rows).
DROP TABLE IF EXISTS bronze.raw_constructors;
CREATE TABLE bronze.raw_constructors (
    -- Constructor Profile & Visual Identity
    year            TEXT,  -- Championship season (2023, 2024, 2025)
    team_name       TEXT,  -- Official constructor team name
    team_colour     TEXT,  -- Brand livery hex color code without '#' (e.g., 3671C6)
    drivers         TEXT,  -- Comma-separated list of driver acronyms active that season
    races           TEXT,  -- Total Grands Prix contested in the season (22 or 24)
    final_points    TEXT,  -- Total season championship points scored
    final_position  TEXT,  -- World Constructors' Championship finishing position (1-10)
    -- Medallion Audit Lineage Columns
    _ingested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file    TEXT      NOT NULL DEFAULT 'Constructors.csv'
);

-- Table: bronze.raw_race_results
-- Description: Raw staging table for Race_Results.csv (1,397 rows).
DROP TABLE IF EXISTS bronze.raw_race_results;
CREATE TABLE bronze.raw_race_results (
    -- Session & Calendar Hierarchy
    year               TEXT,  -- Championship season (2023, 2024, 2025)
    round              TEXT,  -- Round number in championship
    meeting_key        TEXT,  -- Grand Prix meeting identifier
    meeting_name       TEXT,  -- Grand Prix event name
    session_key        TEXT,  -- Unique race session key
    session_name       TEXT,  -- Session name ('Race')
    circuit_short_name TEXT,  -- Circuit location identifier
    country_name       TEXT,  -- Host country
    -- Driver Result Classification
    position           TEXT,  -- Official finishing rank (1-20; NULL if DNF/DNS/DSQ)
    driver_number      TEXT,  -- Permanent racing number
    number_of_laps     TEXT,  -- Total race laps completed by driver
    points             TEXT,  -- Championship points awarded
    dnf                TEXT,  -- Boolean string: Did Not Finish (True/False)
    dns                TEXT,  -- Boolean string: Did Not Start (True/False)
    dsq                TEXT,  -- Boolean string: Disqualified (True/False)
    duration           TEXT,  -- Total race time in seconds (NULL for non-finishers)
    gap_to_leader      TEXT,  -- Margin behind winner (seconds or '+N LAP' string)
    name_acronym       TEXT,  -- Three-letter driver acronym
    full_name          TEXT,  -- Full driver name
    team_name          TEXT,  -- Constructor team name
    -- Medallion Audit Lineage Columns
    _ingested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _source_file       TEXT      NOT NULL DEFAULT 'Race_Results.csv'
);

-- ---------------------------------------------------------------------------
-- Task 1.8: Bulk Load Staging Tables
-- Blank CSV fields become NULL. Source text is otherwise strictly preserved.
-- ---------------------------------------------------------------------------

\copy bronze.raw_drivers (year, driver_number, full_name, name_acronym, broadcast_name, team_name, team_colour, races_entered, first_round, last_round, final_points, final_position) FROM '/home/mohamed/F1/raw_data/Drivers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_constructors (year, team_name, team_colour, drivers, races, final_points, final_position) FROM '/home/mohamed/F1/raw_data/Constructors.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy bronze.raw_race_results (year, round, meeting_key, meeting_name, session_key, session_name, circuit_short_name, country_name, position, driver_number, number_of_laps, points, dnf, dns, dsq, duration, gap_to_leader, name_acronym, full_name, team_name) FROM '/home/mohamed/F1/raw_data/Race_Results.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ---------------------------------------------------------------------------
-- Task 1.9: Diagnostics & Data Profiling
-- ---------------------------------------------------------------------------

-- Drivers count and distinct drivers per season
SELECT
    year,
    COUNT(*) AS row_count,
    COUNT(DISTINCT driver_number) AS distinct_driver_number
FROM bronze.raw_drivers
GROUP BY year
ORDER BY year;

-- Driver duplicate analysis: detecting mid-season team swaps and team_colour case variations
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

-- Race results profiling: non-numeric gap_to_leader strings (+N LAP), position NULLs, duration NULLs
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
-- Task 1.10: Master Ingestion Audit Summary View
-- One comprehensive audit row per bronze table profiling row volume, column
-- count, total null cells, and duplicate key groupings.
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
