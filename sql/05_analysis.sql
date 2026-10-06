-- =====================================================================
-- 05_analysis.sql
-- Purpose : Answer the five analysis questions by building one small
--           summary table per question.
-- Input   : table trips_clean
-- Output  : summary tables q1_* to q5_*, read by
--           notebooks/analysis.ipynb
-- =====================================================================

-- CLI display settings (DuckDB shell commands)
.timer on
.echo on
.maxwidth 0

-- ---------------------------------------------------------------------
-- [0] Rides used in Q5
--     Q5 ranks start stations, so every ride needs a start station name. A classic bike must be
--     docked at a Divvy station at the end of a ride, so classic bike rides also need an
--     end station name. An electric bike can be locked outside a station, so electric bike rides 
--     with no end station name are kept.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS trips_q5;

CREATE VIEW trips_q5 AS
SELECT *
FROM trips_clean
WHERE start_station_name IS NOT NULL
  AND (end_station_name IS NOT NULL OR rideable_type = 'electric_bike');

-- 0-1 Count of rides used in Q5
SELECT COUNT(*) AS q5_rides
FROM trips_q5;

-- Result: 4,690,815 rows

-- 0-2 Check whether the cleaned table matches the rules
-- Expect: no ride should be missing a start station name, and no classic bike ride should be 
--         missing an end station name.
SELECT rideable_type,
       COUNT(*) AS n_rides,
       SUM(CASE WHEN start_station_name IS NULL THEN 1 ELSE 0 END) AS n_no_start_station,
       SUM(CASE WHEN end_station_name   IS NULL THEN 1 ELSE 0 END) AS n_no_end_station
FROM trips_q5
GROUP BY rideable_type
ORDER BY rideable_type;

-- Result: no missing start name in both classic bike rides and electric bike rides, and no missing 
--         end station in classic bike rides.

-- ---------------------------------------------------------------------
-- [1] Q1 How many rides do casual and member riders take, 
--     and what is their share of the total?
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS q1_ride_counts;

CREATE TABLE q1_ride_counts AS
SELECT member_casual,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM trips_clean
GROUP BY member_casual;

SELECT *
FROM q1_ride_counts
ORDER BY n_rides DESC;

-- Results:
--   Members: 3,802,698 / 64.77%
--   Casual riders: 2,068,692 / 35.23%

-- ---------------------------------------------------------------------
-- [2] Q2 How long does each rider type ride?
-- ---------------------------------------------------------------------

-- 2-1 Summary statistics (in minutes)
DROP TABLE IF EXISTS q2_duration_stats;

CREATE TABLE q2_duration_stats AS
SELECT member_casual,
       COUNT(*) AS n_rides,
       ROUND(AVG(ride_minutes), 2) AS mean_minutes,
       ROUND(MIN(ride_minutes), 2) AS min_minutes,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ride_minutes), 2) AS p25_minutes,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ride_minutes), 2) AS median_minutes,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ride_minutes), 2) AS p75_minutes,
       ROUND(MAX(ride_minutes), 2) AS max_minutes
FROM (
    SELECT member_casual,
           EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0 AS ride_minutes
    FROM trips_clean
) AS rides_with_duration
GROUP BY member_casual;

SELECT *
FROM q2_duration_stats
ORDER BY median_minutes DESC;

-- Results:
--   Casual riders: Mean = 18.90 mins, Median = 11.48 mins, Interquartile Range = 6.63 - 20.72 (Right-skewed distribution)
--   Members: Mean = 12.26 mins, Median = 8.75 mins, Interquartile Range = 5.22 - 14.76 (Right-skewed distribution)

-- 2-2 Distribution of ride durations
DROP TABLE IF EXISTS q2_duration_buckets;

CREATE TABLE q2_duration_buckets AS
SELECT member_casual,
       bucket_order,
       duration_bucket,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS share_within_group
FROM (
    SELECT member_casual,
           CASE
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) <  300  THEN 1
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) <  600  THEN 2
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 1200  THEN 3
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 1800  THEN 4
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 3600  THEN 5
               ELSE 6
           END AS bucket_order,
           CASE
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) <  300  THEN 'under 5 min'
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) <  600  THEN '5 to 10 min'
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 1200  THEN '10 to 20 min'
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 1800  THEN '20 to 30 min'
               WHEN EXTRACT(EPOCH FROM (ended_at - started_at)) < 3600  THEN '30 to 60 min'
               ELSE '60 min and over'
           END AS duration_bucket
    FROM trips_clean
) AS bucketed_rides
GROUP BY member_casual, bucket_order, duration_bucket;

SELECT *
FROM q2_duration_buckets
ORDER BY member_casual, bucket_order;

-- Observations:
--      For the bucket of 60 minutes and over rides, casual riders have a much higher share (4.3%)
--      than members (0.67%). This is consistent with the fact that casual riders have a higher mean ride 
--      duration than members, since the casual riders' mean is pulled up by a few large values.


-- ---------------------------------------------------------------------
-- [3] Q3 At what time of day does each rider type start a ride?
-- ---------------------------------------------------------------------

-- Count of rides by hour of a day (0-23) by rider types
DROP TABLE IF EXISTS q3_rides_by_hour;

CREATE TABLE q3_rides_by_hour AS
SELECT member_casual,
       start_hour,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS share_within_group
FROM (
    SELECT member_casual,
           EXTRACT(HOUR FROM started_at) AS start_hour
    FROM trips_clean
) AS rides_with_hour
GROUP BY member_casual, start_hour;

.maxrows 60
SELECT *
FROM q3_rides_by_hour
ORDER BY member_casual, start_hour;

-- Observations:
--   1. Casual riders start riding more frequently between 11:00 and 19:00, with usage peaking at 17:00.
--   2. Members rides show two peaks at 8:00 (7.3%) and 17:00 (10.78%), which are typical commuting hours. 

-- ---------------------------------------------------------------------
-- [4] Q4 Which bike type does each rider type choose?
-- ---------------------------------------------------------------------

-- Count of rides by bike types for casual riders and members
DROP TABLE IF EXISTS q4_bike_type;

CREATE TABLE q4_bike_type AS
SELECT member_casual,
       rideable_type,
       COUNT(*) AS n_rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS share_within_group
FROM trips_clean
GROUP BY member_casual, rideable_type;

SELECT *
FROM q4_bike_type
ORDER BY member_casual, n_rides DESC;

-- Results
--   1. Casual riders: electric bikes = 70.62%, classic bikes = 29.38%
--   2. Members: electric bikes = 66.4%, classic bikes = 33.6% 

-- ---------------------------------------------------------------------
-- [5] Q5 What is the difference in starting stations between casual riders and members?
-- ---------------------------------------------------------------------

-- 5-1 Create a summary table of all start stations with their total rides and casual share
DROP TABLE IF EXISTS q5_station_summary;

CREATE TABLE q5_station_summary AS
SELECT start_station_name AS station_name,
       COUNT(*) AS n_rides,
       SUM(CASE WHEN member_casual = 'casual' THEN 1 ELSE 0 END) AS n_casual,
       SUM(CASE WHEN member_casual = 'member' THEN 1 ELSE 0 END) AS n_member,
       ROUND(100.0 * SUM(CASE WHEN member_casual = 'casual' THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS casual_share_pct,
       ROUND(AVG(start_lat), 5) AS lat,
       ROUND(AVG(start_lng), 5) AS lng
FROM trips_q5
GROUP BY start_station_name;

-- Check whether the number of rows is consistent with 'trips_q5' table
SELECT COUNT(*)     AS n_stations,
       SUM(n_rides) AS total_rides
FROM q5_station_summary;

-- Overall casual share in trips_q5, used as the midpoint of the map colors
SELECT ROUND(100.0 * SUM(n_casual) / SUM(n_rides), 2) AS casual_share_pct
FROM q5_station_summary;

-- Export all stations for the overall map
COPY (
    SELECT station_name, n_rides, n_casual, n_member, casual_share_pct, lat, lng
    FROM q5_station_summary
    ORDER BY n_rides DESC
) TO 'data/processed/q5_all_stations.csv' (HEADER, DELIMITER ',');

-- Results: 1,955 start stations, 4,690,815 rows (matches [0])

-- 5-2 Top 20 start stations for both casual riders and members
DROP TABLE IF EXISTS q5_top_stations;

CREATE TABLE q5_top_stations AS
SELECT ranked_stations.member_casual,
       ranked_stations.station_rank,
       ranked_stations.station_name,
       ranked_stations.n_rides_by_group,
       q5_station_summary.casual_share_pct,
       q5_station_summary.lat,
       q5_station_summary.lng
FROM (
    SELECT member_casual,
           start_station_name AS station_name,
           COUNT(*) AS n_rides_by_group,
           ROW_NUMBER() OVER (PARTITION BY member_casual
                              ORDER BY COUNT(*) DESC,
                                       start_station_name) AS station_rank
    FROM trips_q5
    GROUP BY member_casual, start_station_name
) AS ranked_stations
JOIN q5_station_summary
  ON ranked_stations.station_name = q5_station_summary.station_name
WHERE ranked_stations.station_rank <= 20;

SELECT *
FROM q5_top_stations
ORDER BY member_casual, station_rank;

-- Observations:
--   1. It seems that commonly used stations for casual riders are located near lakeside scenic spots,
--      while those for members are located near public transportation stations. 
--      (Initial search results from entering coordinates into Google Maps)
--   2. Some stations overlap between the top 20 commonly used stations lists for both groups. 
--      (Ex: Navy Pier, DuSable Lake Shore Dr & North Blvd, Wells St & Concord Ln, Clark St & Armitage Ave,
--       and Clark St & Lincoln Ave)

-- 5-3 What percentage of total rides do the top 20 stations account for?
SELECT top_totals.member_casual,
       top_totals.n_rides_top_20,
       group_totals.n_rides_all,
       ROUND(100.0 * top_totals.n_rides_top_20 / group_totals.n_rides_all, 2) AS top_20_share_pct
FROM (
    SELECT member_casual,
           SUM(n_rides_by_group) AS n_rides_top_20
    FROM q5_top_stations
    GROUP BY member_casual
) AS top_totals
JOIN (
    SELECT member_casual,
           COUNT(*) AS n_rides_all
    FROM trips_q5
    GROUP BY member_casual
) AS group_totals
  ON top_totals.member_casual = group_totals.member_casual
ORDER BY top_totals.member_casual;

-- Results: 
--   top 20 stations share percentage for casual riders: 18.53%
--   top 20 stations share percentage for members: 11.28%

-- Interpretation:
--   Even though the top 20 stations account for nearly 20% of casual rides, findings from these stations cannot be applied
--   to the whole network since 81.47% of casual rides are scattered across hundreds of other stations. 

-- 5-4 Check whether top 20 stations are affected by station name and ID mismatch
--     If a result is displayed, it means that a specific ID from a popular station 
--     is also registered under another station name.
WITH top_station_ids AS (
    SELECT DISTINCT start_station_name AS station_name,
                    start_station_id   AS station_id
    FROM trips_q5
    WHERE start_station_name IN (SELECT station_name FROM q5_top_stations)
)
SELECT top_station_ids.station_name,
       top_station_ids.station_id,
       trips_q5.start_station_name AS other_name,
       SUM(CASE WHEN trips_q5.member_casual = 'casual' THEN 1 ELSE 0 END) AS n_casual,
       SUM(CASE WHEN trips_q5.member_casual = 'member' THEN 1 ELSE 0 END) AS n_member
FROM top_station_ids
JOIN trips_q5
  ON trips_q5.start_station_id    = top_station_ids.station_id
 AND trips_q5.start_station_name <> top_station_ids.station_name
GROUP BY top_station_ids.station_name,
         top_station_ids.station_id,
         trips_q5.start_station_name
ORDER BY top_station_ids.station_name, other_name;

-- Result: 0 rows. The ranking is not affected by station name and ID mismatch.

-- 5-5 Export the top stations for the map in Tableau Public
COPY (
    SELECT member_casual, station_rank, station_name, n_rides_by_group,
           casual_share_pct, lat, lng
    FROM q5_top_stations
    ORDER BY member_casual, station_rank
) TO 'data/processed/q5_top_stations.csv' (HEADER, DELIMITER ',');

-- ---------------------------------------------------------------------
-- [6] Reconciliation
--     Each summary table must add up to the rides it was built from.
-- ---------------------------------------------------------------------
SELECT 'q1_ride_counts' AS summary_table,
       SUM(n_rides) AS total_rides,
       (SELECT COUNT(*) FROM trips_clean) AS expected_rides
FROM q1_ride_counts
UNION ALL
SELECT 'q2_duration_stats', SUM(n_rides), (SELECT COUNT(*) FROM trips_clean)
FROM q2_duration_stats
UNION ALL
SELECT 'q2_duration_buckets', SUM(n_rides), (SELECT COUNT(*) FROM trips_clean)
FROM q2_duration_buckets
UNION ALL
SELECT 'q3_rides_by_hour', SUM(n_rides), (SELECT COUNT(*) FROM trips_clean)
FROM q3_rides_by_hour
UNION ALL
SELECT 'q4_bike_type', SUM(n_rides), (SELECT COUNT(*) FROM trips_clean)
FROM q4_bike_type
UNION ALL
SELECT 'q5_station_summary', SUM(n_rides), (SELECT COUNT(*) FROM trips_q5)
FROM q5_station_summary;

-- Results: The number of rows in each table matches the expected value, indicating that the sub-tables
--          created during our analysis are correct and further validating our analytical results.