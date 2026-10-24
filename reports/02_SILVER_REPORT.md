# Silver Layer Transformation Report

Database `f1_warehouse`, schema `silver`. Bronze text was cast to integer, numeric, boolean, and timestamp. The figures below come from `silver.vw_transformation_audit_log` after the load.

## Mohamed

`silver.fact_race_laps` kept all 77373 bronze rows. 63115 laps are `is_valid_strategy_lap`. 14258 laps were rejected.

Rejection reasons overlap, so the counts below are not a partition of the rejected rows:

- Opening laps: 1394
- Pit in or pit out laps: 4762
- Neutralised laps (safety car, VSC, or red flag): 8132
- Laps slower than 107 percent of the driver's median pace: 8855

The median is `PERCENTILE_CONT(0.5)` per session and driver, computed on laps that are not an opening lap, a pit lap, or a neutralised lap. This PostgreSQL build does not allow `OVER` on that ordered-set aggregate, so the median is grouped and joined back.

Fuel-corrected lap time was rebuilt as `lap_duration + 0.03 * (lap_number - 1)`. Mismatches against the value stored in bronze: 0.

17240 laps had at least one of `i1_speed`, `i2_speed`, or `st_speed` filled from the driver's average on that stint.

## Yousef

`silver.fact_pit_stops` has 2229 rows. 110 bronze rows with `pit_duration` above 60 seconds were removed as red-flag holds. 87 of the kept stops have a stationary time of 5 seconds or more and are marked `is_penalty_stop`. `net_pit_loss_s` is the lane time, and `circuit_avg_pit_loss_s` is the season average for that circuit.

`silver.fact_race_control` has 6278 rows. 8 exact duplicate messages were removed. Flags set on the cleaned messages:

- Safety car events: 111
- Virtual safety car events: 58
- Red flag events: 11
- DRS changes: 359
- Track-limit deletions: 1078
- Steward penalties: 194

A virtual safety car message is not also counted as a safety car. `CHEQUERED FLAG` is not counted as a red flag.

## Mahmud

`silver.dim_races` has 70 rows, and all 70 received a Pirelli hard, medium, and soft code, including C6 where it was nominated in 2025. `date_start` and `date_end` are UTC timestamps.

`silver.fact_weather` keeps race sessions only: 23351 non-race rows were excluded, leaving 11069 race observations. None of the duplicate timestamps were inside a race session, so 0 race rows were removed for duplication. 49 rows are marked as the first minute of rain in a session. `track_temp_delta_prev_5min` is the change versus the sample five minutes earlier.

## Moaz

`silver.dim_drivers` went from 106 bronze rows to 68, removing 38 duplicates. The kept row is the one with the most races entered in that season. 22 hex colours differed only by letter case and were stored with `UPPER`. 9 driver rows and 3 constructor rows carry a lineage name: Alfa Romeo to Kick Sauber, and AlphaTauri or RB to Racing Bulls. The season's own `team_name` is unchanged. `silver.dim_constructors` stays at 30 rows.

`silver.fact_race_results` has 1397 rows. 923 gaps are numeric seconds. 297 finishers are one or more laps down, parsed from `+N LAP`.

`silver.fact_stint_summary` has 3934 rows, and all 3934 now have a `compound_code`, taken from `silver.dim_races` for HARD, MEDIUM, and SOFT. Each stint also stores the average fuel-corrected time of its valid laps from `silver.fact_race_laps`.

## Exported files

`sql/03_exports/export_bronze_silver.sql` wrote each silver table to CSV. Row counts match the transformation audit.

| Team member | File | Rows |
| --- | --- | ---: |
| Mohamed | exports/silver/mohamed/fact_race_laps.csv | 77373 |
| Yousef | exports/silver/yousef/fact_pit_stops.csv | 2229 |
| Yousef | exports/silver/yousef/fact_race_control.csv | 6278 |
| Mahmud | exports/silver/mahmud/dim_races.csv | 70 |
| Mahmud | exports/silver/mahmud/fact_weather.csv | 11069 |
| Moaz | exports/silver/moaz/dim_drivers.csv | 68 |
| Moaz | exports/silver/moaz/dim_constructors.csv | 30 |
| Moaz | exports/silver/moaz/fact_race_results.csv | 1397 |
| Moaz | exports/silver/moaz/fact_stint_summary.csv | 3934 |
| Moaz | exports/silver/silver_audit_log.csv | 46 |
