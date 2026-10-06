-- =====================================================================
-- 01_import.sql
-- Purpose : Combine 12 months of Divvy trip data (Aug 2025 - Jul 2026)
--           into a single table, and verify the merge is complete.
-- Source  : https://divvy-tripdata.s3.amazonaws.com/index.html
--           (made available by Motivate International Inc. under license)
-- Input   : 12 monthly CSV files in data/raw/
-- Output  : table trips_raw (stored in data/divvy.duckdb)
-- =====================================================================

.timer on
.echo on

-- ---------------------------------------------------------------------
-- [1] Import: stack the 12 CSV files into one table.
--     ID columns are forced to VARCHAR: they are codes, not numbers.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS trips_raw;
CREATE TABLE trips_raw AS
SELECT *
FROM read_csv(
    [
        'data/raw/202508-divvy-tripdata.csv',
        'data/raw/202509-divvy-tripdata.csv',
        'data/raw/202510-divvy-tripdata.csv',
        'data/raw/202511-divvy-tripdata.csv',
        'data/raw/202512-divvy-tripdata.csv',
        'data/raw/202601-divvy-tripdata.csv',
        'data/raw/202602-divvy-tripdata.csv',
        'data/raw/202603-divvy-tripdata.csv',
        'data/raw/202604-divvy-tripdata.csv',
        'data/raw/202605-divvy-tripdata.csv',
        'data/raw/202606-divvy-tripdata.csv',
        'data/raw/202607-divvy-tripdata.csv'
    ],
    header   = true,
    filename = true,      -- adds a column recording each row's source file
    types    = {
        'ride_id':          'VARCHAR',
        'start_station_id': 'VARCHAR',
        'end_station_id':   'VARCHAR'
    }
);

-- ---------------------------------------------------------------------
-- [2] Verify the import
-- ---------------------------------------------------------------------

-- 2-1 Column names and types
--     (expected: 13 columns + filename; started_at / ended_at as TIMESTAMP)
SELECT column_name,
       data_type
FROM information_schema.columns
WHERE table_name = 'trips_raw'
ORDER BY ordinal_position;

-- 2-2 Total row count (6,037,968 rows)
SELECT COUNT(*) AS total_rows
FROM trips_raw;

-- 2-3 Row count per source file
--     (expected: 12 rows, one per month, none close to zero)
SELECT filename,
       COUNT(*) AS n_rows
FROM trips_raw
GROUP BY filename
ORDER BY filename;