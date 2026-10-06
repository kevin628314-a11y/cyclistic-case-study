-- =====================================================================
-- 03_investigate.sql
-- Purpose : Look closely at the rows behind each issue found in
--           02_profile.sql, to understand the problem before deciding
--           how to handle it.
-- Input   : table trips_raw
-- Output  : query results; decisions are recorded in docs/cleaning_log.md
-- =====================================================================

-- CLI display settings (DuckDB shell commands)
.timer on
.echo on
.maxwidth 0

-- ---------------------------------------------------------------------
-- [1] Duplicate ride_id (profile check 3)
-- ---------------------------------------------------------------------

-- 1-1 Show every row whose ride_id appears more than once, with all columns
SELECT ride_id,
       filename,
       rideable_type,
       started_at,
       ended_at,
       start_station_name,
       start_station_id,
       end_station_name,
       end_station_id,
       start_lat,
       start_lng,
       end_lat,
       end_lng,
       member_casual
FROM trips_raw
WHERE ride_id IN (
    SELECT ride_id
    FROM trips_raw
    GROUP BY ride_id
    HAVING COUNT(*) > 1
)
ORDER BY ride_id, filename;

-- 1-2 Count how many rows and how many distinct ride_id values are involved in 
--     those rows whose ride_id appears more than once.
SELECT COUNT(*) AS rows_with_duplicated_ride_id
FROM trips_raw
WHERE ride_id IN (
    SELECT ride_id FROM trips_raw GROUP BY ride_id HAVING COUNT(*) > 1
);

SELECT COUNT(DISTINCT ride_id) AS distinct_duplicated_ride_ids
FROM trips_raw
WHERE ride_id IN (
    SELECT ride_id FROM trips_raw GROUP BY ride_id HAVING COUNT(*) > 1
);

--  Result: 70 rows with duplicated ride_id across 35 ride_id values ,
--  meaning each of these rides appears exactly twice.
--  (two copies hold the same values across all columns is shown by 02_profile.sql 3-2.)

-- ---------------------------------------------------------------------
-- [2] Rides that start outside the analysis window (profile check 6)
-- ---------------------------------------------------------------------

-- 2-1 Show every affected row with all columns.
SELECT ride_id,
       filename,
       rideable_type,
       started_at,
       ended_at,
       start_station_name,
       end_station_name,
       member_casual
FROM trips_raw
WHERE started_at <  TIMESTAMP '2025-08-01 00:00:00'
   OR started_at >= TIMESTAMP '2026-08-01 00:00:00'
ORDER BY started_at, filename;

-- ---------------------------------------------------------------------
-- [3] Rides with unusual durations (profile check 7)
-- ---------------------------------------------------------------------

-- 3-1 Duration of zero or less
SELECT ride_id,
       rideable_type,
       started_at,
       ended_at,
       EXTRACT(EPOCH FROM (ended_at - started_at)) AS ride_seconds,
       start_station_name,
       end_station_name,
       member_casual
FROM trips_raw
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) <= 0
ORDER BY started_at;
-- Observation: all 29 rows fall on the same day (2025-11-02)

-- 3-2 Duration under one minute
SELECT ride_id,
       rideable_type,
       started_at,
       ended_at,
       EXTRACT(EPOCH FROM (ended_at - started_at)) AS ride_seconds,
       start_station_name,
       end_station_name,
       member_casual
FROM trips_raw
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) > 0
  AND EXTRACT(EPOCH FROM (ended_at - started_at)) < 60
ORDER BY ride_id
LIMIT 20;
-- Observation: The stations must satisfy one of the following conditions:
--              - Same start and end stations
--              - Both stations are NULL
--              - Valid start station with a NULL end station

-- 3-3 Duration over 24 hours
SELECT ride_id,
       rideable_type,
       started_at,
       ended_at,
       EXTRACT(EPOCH FROM (ended_at - started_at)) AS ride_seconds,
       start_station_name,
       end_station_name,
       member_casual
FROM trips_raw
WHERE EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
ORDER BY ride_id
LIMIT 20;

-- 3-4 Test whether rides over 24 hours are more likely to have no end station recorded.
SELECT CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
            THEN 'over 24 hours'
            ELSE '24 hours or less' END AS duration_group,
       COUNT(*) AS n_rides,
       SUM(CASE WHEN end_station_name IS NULL THEN 1 ELSE 0 END) AS end_station_missing,
       ROUND(100.0 * SUM(CASE WHEN end_station_name IS NULL THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS end_station_missing_pct
FROM trips_raw
GROUP BY CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
              THEN 'over 24 hours'
              ELSE '24 hours or less' END;

-- ---------------------------------------------------------------------
-- [4] Missing station names and station IDs, and end coordinates (profile checks 2 and 8)
-- ---------------------------------------------------------------------

-- 4-1 Count rows by missing value patterns.
--     Note: 1. The start/end station name and ID are always either both present or both missing.
--           2. The start latitude and longitude do not have any missing values.
SELECT start_station_status,
       end_station_status,
       end_lat_status,
       end_lng_status,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM trips_raw), 2) AS pct_of_rides
FROM (
    SELECT CASE WHEN start_station_name IS NULL THEN 'missing' ELSE 'present' END AS start_station_status,
           CASE WHEN end_station_name   IS NULL THEN 'missing' ELSE 'present' END AS end_station_status,
           CASE WHEN end_lat            IS NULL THEN 'missing' ELSE 'present' END AS end_lat_status,
           CASE WHEN end_lng            IS NULL THEN 'missing' ELSE 'present' END AS end_lng_status
    FROM trips_raw
) AS missing_flags
GROUP BY start_station_status, end_station_status, end_lat_status, end_lng_status
ORDER BY n_rides DESC;

-- Observation:
--  1. Rows containing both station names account for 66.46%. 
--     Dropping all rows with missing station names will reduce the total dataset by 33.54%.
--  2. The variables end_lat and end_lng are always missing together. 
--     Furthermore, if the end coordinates are missing, the station names will also be missing.
--  3. The proportion of rows where both the start and end stations are missing is 9.68%.

-- 4-2 Compare a sample of rows with at least one station missing against
--     a sample of rows with both stations present.
SELECT *
FROM (
    SELECT 'station missing' AS sample_group,
           ride_id, rideable_type, start_station_name, end_station_name,
           start_lat, start_lng, end_lat, end_lng, member_casual
    FROM trips_raw
    WHERE start_station_name IS NULL
       OR end_station_name IS NULL
    ORDER BY ride_id
    LIMIT 10
) AS missing_sample
UNION ALL
SELECT *
FROM (
    SELECT 'both stations present' AS sample_group,
           ride_id, rideable_type, start_station_name, end_station_name,
           start_lat, start_lng, end_lat, end_lng, member_casual
    FROM trips_raw
    WHERE start_station_name IS NOT NULL
      AND end_station_name IS NOT NULL
    ORDER BY ride_id
    LIMIT 10
) AS present_sample
ORDER BY sample_group, ride_id;

-- Observation: 
-- 1. The 10 records shown in "station missing" are all electric bikes
--    , while "both stations present" includes both types.
-- 2. For the cells missing a station name, 
--    their corresponding coordinates are limited to a maximum of two decimal places.


-- 4-3 The share of bike types for rows with at least one station missing.
SELECT rideable_type,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_station_missing_rows
FROM trips_raw
WHERE start_station_name IS NULL
   OR end_station_name   IS NULL
GROUP BY rideable_type
ORDER BY rideable_type;

-- Observation: 
--    99.73% of the rows with at least one station missing (2,025,247 rows) are electric bikes

-- 4-4 The share of bike types for rows with both start and end stations missing.
SELECT rideable_type,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_station_missing_rows
FROM trips_raw
WHERE start_station_name IS NULL
   AND end_station_name   IS NULL
GROUP BY rideable_type
ORDER BY rideable_type;

-- Observation: 
--    All of the rows with both stations missing (584,730 rows) are electric bikes.

-- 4-5 Sample of rows with no end coordinates, with ride duration in hours
SELECT ride_id,
       rideable_type,
       started_at,
       ended_at,
       ROUND(EXTRACT(EPOCH FROM (ended_at - started_at)) / 3600, 2) AS ride_hours,
       start_station_name,
       end_station_name,
       member_casual
FROM trips_raw
WHERE end_lat IS NULL
   OR end_lng IS NULL
ORDER BY ride_id
LIMIT 10;

-- Observation: 
-- 1. All 10 rows are classic bikes.
-- 2. All have start station names.
-- 3. The ride durations are concentrated within 24.99 and 25.00 hours.


-- 4-6 Profile all rows with no end coordinates.
SELECT COUNT(*) AS n_rides,
       ROUND(100.0 * SUM(CASE WHEN rideable_type = 'classic_bike'       THEN 1 ELSE 0 END) / COUNT(*), 2) AS classic_bike_pct,
       ROUND(100.0 * SUM(CASE WHEN member_casual = 'casual'             THEN 1 ELSE 0 END) / COUNT(*), 2) AS casual_pct,
       ROUND(100.0 * SUM(CASE WHEN start_station_name IS NOT NULL       THEN 1 ELSE 0 END) / COUNT(*), 2) AS start_station_present_pct,
       ROUND(100.0 * SUM(CASE WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) > 86400
                              THEN 1 ELSE 0 END) / COUNT(*), 2) AS over_24_hours_pct
FROM trips_raw
WHERE end_lat IS NULL
   OR end_lng IS NULL;

-- Observation:
-- 1. All rows (5436 rows) with no end coordinates are classic bikes.
-- 2. 80.81% of these rows are casual riders.
-- 3. All rows have start station names.
-- 4. 94.89% of these rows have ride durations over 24 hours.

-- 4-7 Compare member vs. casual split between all rides and the rides which excluding
--     those with missing start station and classic bikes with no end station names
SELECT ride_group,
       member_casual,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY ride_group), 2) AS pct_within_group
FROM (
    SELECT 'all rides' AS ride_group,
           member_casual
    FROM trips_raw
    UNION ALL
    SELECT 'cleaned rides' AS ride_group,
           member_casual
    FROM trips_raw
    WHERE start_station_name IS NOT NULL
      AND (end_station_name IS NOT NULL OR rideable_type = 'electric_bike')
) AS compared_rides
GROUP BY ride_group, member_casual
ORDER BY member_casual, ride_group;

-- Observation: Excluding these rides barely changes the split between casual riders and members
--              (The member share of all rides is 64.37%, compared to 64.79% for cleaned rides)

-- 4-8 Compare classic_bike vs. electric_bike split between all rides and the rides which 
--     excluding those with missing start station and classic bikes with no end station names
SELECT ride_group,
       rideable_type,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY ride_group), 2) AS pct_within_group
FROM (
    SELECT 'all rides' AS ride_group,
           rideable_type
    FROM trips_raw
    UNION ALL
    SELECT 'cleaned rides' AS ride_group,
           rideable_type
    FROM trips_raw
    WHERE start_station_name IS NOT NULL
      AND (end_station_name IS NOT NULL OR rideable_type = 'electric_bike')
) AS compared_rides
GROUP BY ride_group, rideable_type
ORDER BY rideable_type, ride_group;

-- Observation: After excluding these rows, the share of electric_bike rides drops from 68.68% to 60.38%,
--              and the share ofclassic_bike rides rises from 31.32% to 39.62%.

-- 4-9 Calculate the percentage of classic bike rides and electric bike rides that will be removed
SELECT rideable_type,
       COUNT(*) AS n_rides_all,
       SUM(CASE WHEN start_station_name IS NULL
                  OR (end_station_name IS NULL AND rideable_type = 'classic_bike')
                THEN 1 ELSE 0 END) AS n_rides_excluded,
       ROUND(100.0 * SUM(CASE WHEN start_station_name IS NULL
                                OR (end_station_name IS NULL AND rideable_type = 'classic_bike')
                              THEN 1 ELSE 0 END) / COUNT(*), 2) AS excluded_pct
FROM trips_raw
GROUP BY rideable_type
ORDER BY rideable_type;

-- Observation: 0.29% of classic bike rides and 30.7% of electric bike rides will be removed

-- ---------------------------------------------------------------------
-- [5] Consistency between station ID and station name (profile check 5)
-- ---------------------------------------------------------------------

-- 5-1 Station IDs that map to more than one name, with how often each name is used.
WITH station_uses AS (
    SELECT start_station_id   AS station_id,
           start_station_name AS station_name
    FROM trips_raw
    WHERE start_station_id IS NOT NULL
    UNION ALL
    SELECT end_station_id,
           end_station_name
    FROM trips_raw
    WHERE end_station_id IS NOT NULL
)
SELECT station_id,
       station_name,
       COUNT(*) AS n_uses
FROM station_uses
WHERE station_id IN (
    SELECT station_id
    FROM station_uses
    GROUP BY station_id
    HAVING COUNT(DISTINCT station_name) > 1
)
GROUP BY station_id, station_name
ORDER BY station_id, n_uses DESC;

-- Observation: IDs with more than one name fall into several different cases.
--   1. A number or symbol is added to the name:
--      'Kingsbury St & Kinzie St' (34,777 uses) / 'Kingsbury St & Kinzie St 1' (27,314 uses);
--      'Morgan St & Lake St' / 'Morgan St & Lake St*'
--   2. A label is added to the name: '[Archived] ...', ' ... (temp location)'
--   3. The station was renamed:
--      CHI02101 'LaSalle St & Washington St' / 'Riley O'Neil Memorial Station at City Hall'

-- 5-2 Station names that map to more than one ID, with how often each ID is used.
WITH station_uses AS (
    SELECT start_station_id   AS station_id,
           start_station_name AS station_name
    FROM trips_raw
    WHERE start_station_id IS NOT NULL
    UNION ALL
    SELECT end_station_id,
           end_station_name
    FROM trips_raw
    WHERE end_station_id IS NOT NULL
)
SELECT station_name,
       station_id,
       COUNT(*) AS n_uses
FROM station_uses
WHERE station_name IN (
    SELECT station_name
    FROM station_uses
    GROUP BY station_name
    HAVING COUNT(DISTINCT station_id) > 1
)
GROUP BY station_name, station_id
ORDER BY station_name, n_uses DESC;

-- Observation: Names with more than one ID also fall into different cases.
--   1. The station has an old and a new ID:
--      'Wilton Ave & Diversey Pkwy' uses both CHI00226 and CHI02052
--   2. A prefix is added to the ID: '(ARCHIVE)CHI02077', '000-CHI01831'


-- Conclusion: 
-- Since these mismatches have several different causes, they cannot be fixed with a single rule.
-- We will do the Q5 and Q6 analysis directly, and see how much they actually affect the results.