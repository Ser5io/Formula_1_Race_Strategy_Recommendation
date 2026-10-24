# Bronze Layer Data Events Report

Database `f1_warehouse`, schema `bronze`. Every source column was loaded as text from `raw_data/`. Blank CSV fields became NULL. Each table carries `_ingested_at` and `_source_file`.

The summary below is the result of `bronze.vw_ingestion_audit_summary`.

| Team member | Table | Rows | Source columns | NULL cells | Duplicate key groups | Extra duplicate rows |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Mohamed | raw_race_laps | 77373 | 54 | 269415 | 0 | 0 |
| Mohamed | raw_stint_summary | 3934 | 24 | 6143 | 0 | 0 |
| Yousef | raw_pit_stops | 2339 | 16 | 1488 | 0 | 0 |
| Yousef | raw_race_control | 6286 | 17 | 22585 | 8 | 8 |
| Mahmud | raw_weather | 34420 | 16 | 0 | 28 | 28 |
| Mahmud | raw_races | 70 | 22 | 210 | 0 | 0 |
| Moaz | raw_drivers | 106 | 12 | 2 | 34 | 38 |
| Moaz | raw_constructors | 30 | 7 | 0 | 0 | 0 |
| Moaz | raw_race_results | 1397 | 20 | 811 | 0 | 0 |

## Mohamed

`raw_race_laps` holds 24479 rows in 2023, 26629 in 2024, and 26265 in 2025. The natural key `(session_key, driver_number, lap_number)` has no duplicates.

NULL counts on the columns used later: `lap_duration` 258, `i1_speed` 12294, `i2_speed` 1119, `st_speed` 6606, `compound_code` 73084, `deg_vs_stint_best_s` 14258.

`raw_stint_summary` has no duplicate `(session_key, driver_number, stint_number)`. Most of its NULL cells are empty `compound_code` values and stints with no clean-lap slope.

## Yousef

`raw_pit_stops` has a `stop_duration` on only part of the extract. The 1488 NULL cells are those missing stationary times. `lane_duration` and `pit_duration` are populated, and `(session_key, driver_number, lap_number)` is unique.

`raw_race_control` has 8 repeated `(session_key, date, message)` groups, 8 extra rows. `driver_number` and `flag` are blank on a large share of messages because many race-control lines are track-wide rather than aimed at one car. Categories observed: Flag, Other, Drs, SessionStatus, SafetyCar, CarEvent.

## Mahmud

`raw_weather` covers Race, Qualifying, Practice 1, Practice 2, Practice 3, Sprint, and Sprint Qualifying. No measurement column is NULL. 28 `(session_key, date)` groups are duplicated, 28 extra rows.

`raw_races` has 70 race sessions: 22 in 2023, 24 in 2024, 24 in 2025. All 210 NULL cells are `c_hard`, `c_medium`, and `c_soft` (70 races times 3 columns). `date_start` is `YYYY-MM-DD HH:MM:SS` with no offset. `date_end` is ISO-8601 with a `T` and a `+00:00` offset. Both represent UTC.

## Moaz

`raw_drivers` has 34 `(year, driver_number)` groups with more than one row, 38 extra rows. The repeats are mid-season team changes and hex case differences such as `3671C6` and `3671c6`.

`raw_constructors` has one row per team per season and no duplicate key.

`raw_race_results` has 297 non-numeric `gap_to_leader` values, all of the form `+N LAP` or `+N LAPS`. 154 rows have no `position`. 473 rows have no `duration`. The key `(session_key, driver_number)` is unique.

## Exported files

`sql/03_exports/export_bronze_silver.sql` wrote each bronze table to CSV. Row counts match the audit view.

| Team member | File | Rows |
| --- | --- | ---: |
| Mohamed | exports/bronze/raw_race_laps.csv | 77373 |
| Mohamed | exports/bronze/raw_stint_summary.csv | 3934 |
| Yousef | exports/bronze/raw_pit_stops.csv | 2339 |
| Yousef | exports/bronze/raw_race_control.csv | 6286 |
| Mahmud | exports/bronze/raw_weather.csv | 34420 |
| Mahmud | exports/bronze/raw_races.csv | 70 |
| Moaz | exports/bronze/raw_drivers.csv | 106 |
| Moaz | exports/bronze/raw_constructors.csv | 30 |
| Moaz | exports/bronze/raw_race_results.csv | 1397 |
| Moaz | exports/bronze/bronze_audit_summary.csv | 9 |
