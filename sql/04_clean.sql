-- =====================================================================
-- 04_clean.sql
-- Purpose : Build the cleaned table by applying the decisions recorded
--           in docs/cleaning_log.md.
-- Input   : table trips_raw (never modified)
-- Output  : table trips_clean (stored in data/divvy.duckdb)
-- =====================================================================

-- CLI display settings (DuckDB shell commands)
.timer on
.echo on
.maxwidth 0

-- ---------------------------------------------------------------------
-- [1] Create trips_clean, and remove duplicate rides and trim station fields
--     - 35 ride_id values appear twice with identical values
--       (02_profile.sql 3-2). Only the copy from the earlier file is kept.
--     - Station names and IDs are trimmed of redundant spaces.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS trips_clean;

CREATE TABLE trips_clean AS
SELECT ride_id,
       rideable_type,
       started_at,
       ended_at,
       TRIM(start_station_name) AS start_station_name,
       TRIM(start_station_id)   AS start_station_id,
       TRIM(end_station_name)   AS end_station_name,
       TRIM(end_station_id)     AS end_station_id,
       start_lat,
       start_lng,
       end_lat,
       end_lng,
       member_casual,
       filename
FROM (
    SELECT trips_raw.*,
           ROW_NUMBER() OVER (PARTITION BY ride_id ORDER BY filename) AS copy_number
    FROM trips_raw
) AS numbered_rides
WHERE copy_number = 1;

-- 1-1 Rows after removing duplicates 
-- Expected: 6,037,968 - 35 = 6,037,933
SELECT COUNT(*) AS rows_after_step_1
FROM trips_clean;

-- 6037933 rows

-- ---------------------------------------------------------------------
-- [2] Remove invalid rides
-- ---------------------------------------------------------------------

-- 2-1 Delete rides with a zero or negative duration.
DELETE FROM trips_clean
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) <= 0;

SELECT COUNT(*) AS rows_after_step_2_1
FROM trips_clean;

-- 6037904 rows

-- 2-2 Delete rides shorter than 60 seconds
DELETE FROM trips_clean
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) < 60;

SELECT COUNT(*) AS rows_after_step_2_2
FROM trips_clean;

-- 5877002 rows

-- 2-3 Delete rides longer than 24 hours
DELETE FROM trips_clean
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400;

SELECT COUNT(*) AS rows_after_step_2_3
FROM trips_clean;

-- 5871668 rows

-- 2-4 Delete rows with no end coordinates
DELETE FROM trips_clean
WHERE end_lat IS NULL
   OR end_lng IS NULL;

SELECT COUNT(*) AS rows_after_step_2_4
FROM trips_clean;

-- 5871390 rows

-- ---------------------------------------------------------------------
-- [3] Validate trips_clean
--     Each check counts the rows that still break a cleaning rule.
--     Every check should return 0 violations.
-- ---------------------------------------------------------------------

-- 3-1 All cleaning rules in one result
SELECT 'duplicate ride_id' AS check_name,
       COUNT(*) - COUNT(DISTINCT ride_id) AS violations
FROM trips_clean
UNION ALL
SELECT 'duration outside 60 to 86,400 seconds',
       COUNT(*)
FROM trips_clean
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) < 60
   OR EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
UNION ALL
SELECT 'missing end coordinates',
       COUNT(*)
FROM trips_clean
WHERE end_lat IS NULL
   OR end_lng IS NULL
UNION ALL
SELECT 'station name or ID with leading or trailing spaces',
       COUNT(*)
FROM trips_clean
WHERE start_station_name <> TRIM(start_station_name)
   OR start_station_id   <> TRIM(start_station_id)
   OR end_station_name   <> TRIM(end_station_name)
   OR end_station_id     <> TRIM(end_station_id);

-- ---------------------------------------------------------------------
-- [4] Impact check: does cleaning change the comparison between
--     members and casual riders?
-- ---------------------------------------------------------------------

-- 4-1 Percentage of rides dropped per rider type
SELECT raw_counts.member_casual,
       raw_counts.n_raw,
       clean_counts.n_clean,
       raw_counts.n_raw - clean_counts.n_clean AS n_removed,
       ROUND(100.0 * (raw_counts.n_raw - clean_counts.n_clean) / raw_counts.n_raw, 2) AS pct_removed
FROM (
    SELECT member_casual,
           COUNT(*) AS n_raw
    FROM trips_raw
    GROUP BY member_casual
) AS raw_counts
JOIN (
    SELECT member_casual,
           COUNT(*) AS n_clean
    FROM trips_clean
    GROUP BY member_casual
) AS clean_counts
  ON raw_counts.member_casual = clean_counts.member_casual
ORDER BY raw_counts.member_casual;

-- Observation: Both groups lose a similar numbe of rides (82,361 casual riders vs 84,217 members),
--              but casual riders see a higher drop rate (3.83% vs 2.17%) because their overall 
--              volume is smaller.

-- 4-2 Trip share and ride times by rider type—before vs. after cleaning
SELECT dataset,
       member_casual,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY dataset), 2) AS share_pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ride_minutes), 2) AS median_minutes,
       ROUND(AVG(ride_minutes), 2) AS mean_minutes
FROM (
    SELECT 'raw' AS dataset,
           member_casual,
           EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0 AS ride_minutes
    FROM trips_raw
    UNION ALL
    SELECT 'clean' AS dataset,
           member_casual,
           EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0 AS ride_minutes
    FROM trips_clean
) AS compared_rides
GROUP BY dataset, member_casual
ORDER BY member_casual, dataset DESC;

-- Observations:
-- 1. The percentage of casual riders moves slightly from 35.63% to 35.23%.
-- 2. Median duration for both groupsbarely changes (casual 11.06 -> 11.48, member 8.58 -> 8.75),
--    the median gap therfore moves from 2.48 to 2.73 minutes, while casual riders still ride longer.
-- 3. The casual mean drops from 21.25 to 18.90 minutes, because most of the removed rides over 24 hours 
--    were casual rides. The mean is pulled by a few extreme values while the median is not, 
--    so median duration would be an appropriate measrement for Q2.

-- Conclusion: cleaning does not change the comparison between the two groups.