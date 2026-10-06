-- =====================================================================
-- 02_profile.sql
-- Purpose : Profile trips_raw before cleaning. This script only reads
--           data; it does not change anything.
-- Input   : table trips_raw
-- Output  : query results; findings are recorded in docs/cleaning_log.md
-- SQL     : ANSI SQL. Where ANSI has no equivalent, PostgreSQL syntax
--           is used and the MySQL equivalent is noted in a comment.
-- =====================================================================

-- CLI display settings (DuckDB shell commands, not SQL)
.timer on
.echo on

-- ---------------------------------------------------------------------
-- [1] Structure
-- ---------------------------------------------------------------------

-- 1-1 Column names and data types
SELECT column_name,
       data_type
FROM information_schema.columns
WHERE table_name = 'trips_raw'
ORDER BY ordinal_position;

-- 1-2 Total number of rows
SELECT COUNT(*) AS total_rows
FROM trips_raw;

-- ---------------------------------------------------------------------
-- [2] Missing values
-- ---------------------------------------------------------------------

-- 2-1 NULL value check: count of NULLs and percentage of NULLs for each column
SELECT 'ride_id' AS column_name,
       COUNT(*) - COUNT(ride_id) AS null_count,
       ROUND(100.0 * (COUNT(*) - COUNT(ride_id)) / COUNT(*), 2) AS null_pct
FROM trips_raw
UNION ALL
SELECT 'rideable_type', COUNT(*) - COUNT(rideable_type),
       ROUND(100.0 * (COUNT(*) - COUNT(rideable_type)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'started_at', COUNT(*) - COUNT(started_at),
       ROUND(100.0 * (COUNT(*) - COUNT(started_at)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'ended_at', COUNT(*) - COUNT(ended_at),
       ROUND(100.0 * (COUNT(*) - COUNT(ended_at)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'start_station_name', COUNT(*) - COUNT(start_station_name),
       ROUND(100.0 * (COUNT(*) - COUNT(start_station_name)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'start_station_id', COUNT(*) - COUNT(start_station_id),
       ROUND(100.0 * (COUNT(*) - COUNT(start_station_id)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'end_station_name', COUNT(*) - COUNT(end_station_name),
       ROUND(100.0 * (COUNT(*) - COUNT(end_station_name)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'end_station_id', COUNT(*) - COUNT(end_station_id),
       ROUND(100.0 * (COUNT(*) - COUNT(end_station_id)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'start_lat', COUNT(*) - COUNT(start_lat),
       ROUND(100.0 * (COUNT(*) - COUNT(start_lat)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'start_lng', COUNT(*) - COUNT(start_lng),
       ROUND(100.0 * (COUNT(*) - COUNT(start_lng)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'end_lat', COUNT(*) - COUNT(end_lat),
       ROUND(100.0 * (COUNT(*) - COUNT(end_lat)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'end_lng', COUNT(*) - COUNT(end_lng),
       ROUND(100.0 * (COUNT(*) - COUNT(end_lng)) / COUNT(*), 2)
FROM trips_raw
UNION ALL
SELECT 'member_casual', COUNT(*) - COUNT(member_casual),
       ROUND(100.0 * (COUNT(*) - COUNT(member_casual)) / COUNT(*), 2)
FROM trips_raw;

-- 2-2 Empty strings check (a value that is present but empty)
SELECT 'ride_id' AS column_name,
       SUM(CASE WHEN TRIM(ride_id) = '' THEN 1 ELSE 0 END) AS blank_count
FROM trips_raw
UNION ALL
SELECT 'rideable_type',
       SUM(CASE WHEN TRIM(rideable_type) = '' THEN 1 ELSE 0 END)
FROM trips_raw
UNION ALL
SELECT 'start_station_name',
       SUM(CASE WHEN TRIM(start_station_name) = '' THEN 1 ELSE 0 END)
FROM trips_raw
UNION ALL
SELECT 'start_station_id',
       SUM(CASE WHEN TRIM(start_station_id) = '' THEN 1 ELSE 0 END)
FROM trips_raw
UNION ALL
SELECT 'end_station_name',
       SUM(CASE WHEN TRIM(end_station_name) = '' THEN 1 ELSE 0 END)
FROM trips_raw
UNION ALL
SELECT 'end_station_id',
       SUM(CASE WHEN TRIM(end_station_id) = '' THEN 1 ELSE 0 END)
FROM trips_raw
UNION ALL
SELECT 'member_casual',
       SUM(CASE WHEN TRIM(member_casual) = '' THEN 1 ELSE 0 END)
FROM trips_raw;

-- 2-3 Find missingness in station_id and station_name fields.
--     Each record should have either both or neither of the pair (station_id and station_name). 
--     Expected: 0 rows where only one of the pair is missing.
SELECT SUM(CASE WHEN (start_station_id IS NULL AND start_station_name IS NOT NULL)
                  OR (start_station_id IS NOT NULL AND start_station_name IS NULL)
                THEN 1 ELSE 0 END) AS start_pair_mismatch,
                -- Count rows where only one of the pair is missing.
       SUM(CASE WHEN (end_station_id IS NULL AND end_station_name IS NOT NULL)
                  OR (end_station_id IS NOT NULL AND end_station_name IS NULL)
                THEN 1 ELSE 0 END) AS end_pair_mismatch
FROM trips_raw;

-- ---------------------------------------------------------------------
-- [3] Duplicate rides
-- ---------------------------------------------------------------------

-- 3-1 Check whether any ride_id appears more than once
SELECT COUNT(*)                           AS total_rows,
       COUNT(DISTINCT ride_id)            AS distinct_ride_ids,
       COUNT(*) - COUNT(DISTINCT ride_id) AS extra_rows,
       ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT ride_id)) / COUNT(*), 4) AS extra_rows_pct
FROM trips_raw;

-- 3-2 Check whether the repeated rows are exact copies
--     Expect: exact_copy_extra_rows = extra_rows from 3-1, 
--     meaning every duplicate is an exact copy.
--     If smaller, some rows share a ride_id but differ in other columns.
SELECT COALESCE(SUM(n_copies - 1), 0) AS exact_copy_extra_rows
FROM (
    SELECT COUNT(*) AS n_copies
    FROM trips_raw
    GROUP BY ride_id, rideable_type, started_at, ended_at,
             start_station_name, start_station_id,
             end_station_name, end_station_id,
             start_lat, start_lng, end_lat, end_lng, member_casual
             -- filename is excluded because it only records the source file
    HAVING COUNT(*) > 1
) AS d;
-- Result: exact_copy_extra_rows = extra_rows = 35

-- ---------------------------------------------------------------------
-- [4] Values in categorical columns
--     List distinct values and their counts for rideable_type and member_casual,
--     to check for typos or unexpected values.
-- ---------------------------------------------------------------------

-- 4-1 rideable_type
SELECT rideable_type,
       COUNT(*) AS n_rows
FROM trips_raw
GROUP BY rideable_type
ORDER BY n_rows DESC;

-- 4-2 member_casual
SELECT member_casual,
       COUNT(*) AS n_rows
FROM trips_raw
GROUP BY member_casual
ORDER BY n_rows DESC;

-- ---------------------------------------------------------------------
-- [5] Check consistency between station_id and station_name
--     Each ID should map to one name, and each name to one ID.
-- ---------------------------------------------------------------------

-- 5-1 Build a list of every distinct (station ID, station name) pair
DROP VIEW IF EXISTS station_pairs;
CREATE VIEW station_pairs AS
SELECT TRIM(start_station_id)   AS station_id,
       TRIM(start_station_name) AS station_name
FROM trips_raw
WHERE start_station_id IS NOT NULL
  AND start_station_name IS NOT NULL
UNION   --   Start and end columns describe the same set of stations, so they are combined.
SELECT TRIM(end_station_id),
       TRIM(end_station_name)
FROM trips_raw
WHERE end_station_id IS NOT NULL
  AND end_station_name IS NOT NULL;

-- 5-2 Count distinct station IDs and distinct station names
SELECT COUNT(DISTINCT station_id)   AS distinct_station_ids,
       COUNT(DISTINCT station_name) AS distinct_station_names
FROM station_pairs;

-- 5-3 Count station IDs that have more than one name
SELECT COUNT(*) AS ids_with_multiple_names
FROM (
    SELECT station_id
    FROM station_pairs
    GROUP BY station_id
    HAVING COUNT(*) > 1
) AS x;

-- 5-4 Count station names that have more than one ID
SELECT COUNT(*) AS names_with_multiple_ids
FROM (
    SELECT station_name
    FROM station_pairs
    GROUP BY station_name
    HAVING COUNT(*) > 1
) AS x;

-- 5-5 Show examples of station IDs with more than one name
SELECT station_id,
       station_name
FROM station_pairs
WHERE station_id IN (
    SELECT station_id
    FROM station_pairs
    GROUP BY station_id
    HAVING COUNT(*) > 1
)
ORDER BY station_id, station_name
LIMIT 20;

-- 5-6 Show examples of station names with more than one ID
SELECT station_name,
       station_id
FROM station_pairs
WHERE station_name IN (
    SELECT station_name
    FROM station_pairs
    GROUP BY station_name
    HAVING COUNT(*) > 1
)
ORDER BY station_name, station_id
LIMIT 20;

DROP VIEW station_pairs;

-- ---------------------------------------------------------------------
-- [6] Time range (between 2025-08-01 and 2026-07-31)
-- ---------------------------------------------------------------------

-- 6-1 Find the earliest and latest ride start and end times
SELECT MIN(started_at) AS earliest_start,
       MAX(started_at) AS latest_start,
       MIN(ended_at)   AS earliest_end,
       MAX(ended_at)   AS latest_end
FROM trips_raw;

-- 6-2 Count rides that start outside the analysis window
SELECT COUNT(*) AS start_outside_window
FROM trips_raw
WHERE started_at <  TIMESTAMP '2025-08-01 00:00:00'
   OR started_at >= TIMESTAMP '2026-08-01 00:00:00';

-- ---------------------------------------------------------------------
-- [7] Ride duration
-- ---------------------------------------------------------------------

-- 7-1 Find the shortest and longest ride durations (in seconds)
SELECT MIN(EXTRACT(EPOCH FROM (ended_at - started_at))) AS shortest_seconds,
       MAX(EXTRACT(EPOCH FROM (ended_at - started_at))) AS longest_seconds
FROM trips_raw;

-- 7-2 Count rides with impossible or unusual durations
SELECT SUM(CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) <= 0
                THEN 1 ELSE 0 END) AS zero_or_negative,
       SUM(CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) > 0
                 AND EXTRACT(EPOCH FROM (ended_at - started_at)) < 60
                THEN 1 ELSE 0 END) AS under_60_seconds,
       SUM(CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
                THEN 1 ELSE 0 END) AS over_24_hours
FROM trips_raw;

-- ---------------------------------------------------------------------
-- [8] Coordinates
--     Initially observed that the records with missing station names only 
--     have latitude and longitude up to two decimal places. 
-- ---------------------------------------------------------------------

-- 8-1 Compare start coordinate precision with whether the start station name is present
SELECT start_station_name_status,
       start_coordinate_precision,
       COUNT(*) AS n_rows
FROM (
    SELECT CASE WHEN start_station_name IS NULL THEN 'missing' ELSE 'present' END
               AS start_station_name_status,
           CASE WHEN start_lat = ROUND(start_lat, 2) AND start_lng = ROUND(start_lng, 2)
                THEN '2 decimals or fewer'
                ELSE 'more than 2 decimals' END
               AS start_coordinate_precision
    FROM trips_raw
) AS s
GROUP BY start_station_name_status, start_coordinate_precision
ORDER BY start_station_name_status, start_coordinate_precision;

-- 8-2 Compare end coordinate precision with whether the end station name is present
SELECT end_station_name_status,
       end_coordinate_precision,
       COUNT(*) AS n_rows
FROM (
    SELECT CASE WHEN end_station_name IS NULL THEN 'missing' ELSE 'present' END
               AS end_station_name_status,
           CASE WHEN end_lat IS NULL OR end_lng IS NULL THEN 'coordinates missing'
                WHEN end_lat = ROUND(end_lat, 2) AND end_lng = ROUND(end_lng, 2)
                THEN '2 decimals or fewer'
                ELSE 'more than 2 decimals' END
               AS end_coordinate_precision
    FROM trips_raw
) AS e
GROUP BY end_station_name_status, end_coordinate_precision
ORDER BY end_station_name_status, end_coordinate_precision;