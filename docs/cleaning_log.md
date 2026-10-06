# Cleaning Log

## 1. Data Source

- **Source:** https://divvy-tripdata.s3.amazonaws.com/index.html
- **License:** Made available by Motivate International Inc. under the Divvy Data License Agreement
- **Files:** 12 monthly CSV files, `202508-divvy-tripdata.csv` to `202607-divvy-tripdata.csv`
- **Raw table:** `trips_raw`, 6,037,968 rows
- **Tools:** DuckDB (SQL), Python (pandas)
- **Publisher's processing note:** According to https://divvybikes.com/system-data, the published data has already been processed to exclude trips taken by staff while servicing the system, and trips shorter than 60 seconds.

## 2. Profiling Results

Script: `sql/02_profile.sql`

| # | Check | Result | Needs handling? (Y/N) |
|---|---|---|---|
| 1 | Structure (columns, data types, row count) | 14 columns (13 source columns + `filename`), all with the expected data types. 6,037,968 rows. | N |
| 2 | Missing values | - Start station ID and name: 1,273,200 missing (21.09%).<br>  - End station ID and name: 1,336,777 missing (22.14%). <br> - End coordinates (`end_lat`, `end_lng`): 5,436 missing (0.09%). <br> - No empty strings. <br> - Station ID and station name are always missing on the same rows. | Y |
| 3 | Uniqueness of `ride_id` | 35 extra rows. <br> Every one is a copy of another row across all data columns. | Y |
| 4 | Values in categorical columns | No unexpected values. <br> - `rideable_type`: `electric_bike`, `classic_bike`. <br> - `member_casual`: `member`, `casual`. | N |
| 5 | Consistency between station ID and station name | 56 station IDs map to more than one name; <br> 67 station names map to more than one ID. | Y |
| 6 | Time range | - 128 rows (0.0021%) start before 2025-08-01. <br> - No rows start after 2026-07-31. | Y |
| 7 | Ride duration | - Zero or negative: 29 rows. <br> - Under 60 seconds: 160,902 rows (2.66%). <br> - Over 24 hours: 5,341 rows (0.09%). <br> - Longest ride: 93,597 seconds (about 26 hours). | Y |
| 8 | Coordinates |  - Start: every row whose coordinates have 2 or fewer decimal places (1,273,200) is missing the station name, and every row with more precise coordinates (4,764,768) has one. <br> - End: every row whose coordinates have 2 or fewer decimal places (1,331,341) is missing the station name, and every row with more precise coordinates (4,701,191) has one. <br> - There are 5,436 rows with no end coordinates have no end station name.  | Y |

## 3. Decisions

| Issue | Rows affected | Action | Rationale | Evidence |
|---|---|---|---|---|
|  There are 35 extra rows that are duplicates of others.  | 35 |  Keep the copy from the earlier file (202604) and remove the later one  |  The ride was recorded twice, causing double-counting in all metrics. Since both records are identical, keeping either one will preserve the data. |  02_profile.sql 3-1, 3-2; <br> 03_investigate.sql [1]  |
|  Some of the data starts before the analysis window (2025-08-01)  | 128 |  Keep those rows  |  The August 2025 file includes 128 rides that started on July 30–31 but ended on August 1, showing that the system groups data by end date. Retaining them aligns perfectly with a strict definition of 'rides that ended between 2025-08-01 and 2026-07-31,' keeping the dataset consistent and verifiable.  |  02_profile.sql [6] <br>  03_investigate.sql [2]  |
|  Rides with a zero or negative duration  | 29 |  Remove  |  All 29 rides started between 01:00 and 01:59 on 2025-11-02, the hour when local clocks were set back for the end of daylight saving time. The recorded end time therefore falls before the start time, so the duration is a clock artifact rather than a real measurement.  |  02_profile.sql [7]; <br> 03_investigate.sql 3-1  |
|  Rides shorter than 60 seconds  | 160,902 | Remove |  The data publisher states that trips under 60 seconds have already been excluded, but these rows are still present, so they do not match the documented definition of the dataset. Short rides like this usually happen when someone takes a bike out and immediately puts it back.  |  https://divvybikes.com/system-data; <br> 02_profile.sql [7]; <br> 03_investigate.sql 3-2  |
|  Rides longer than 24 hours  | 5,341 | Remove |  97.88% of these rides have no end station recorded, compared with 22.07% of all other rides. These look more like bikes that were never returned than rides that actually lasted over a day.  |  02_profile.sql [7]; <br> 03_investigate.sql 3-3, 3-4 |
|  Rides with no end coordinates and no end station name  | 5,436 | Remove |  All of these rides are classic bikes that must be docked when returned, but not a single one shows an end station, and nearly 95% lasted over 24 hours. They probably didn't end normally (e.g., lost, stolen, or auto-closed by the system) and shouldn't be counted as real trips.  |  03_investigate.sql 4-1, 4-6  |
|  Rides with missing start station names, end station names, or both  |  2,025,247  |  Keep these rows for Q1-4. <br> For Q5, exclude rides with no start station name and classic bike rides with no end station name, and keep electric bike rides with no end station name.  |  1. Only Q5 (where each group starts its rides) uses station names, and removing these rows would lead to a 33.54% decrease in rides.  <br> 2. Q5 ranks start stations, so every ride used in Q5 needs a start station name. <br> 3. According to Divvy's parking rules, a classic bike must be docked at a Divvy station when the ride is over, while an electric bike can either be docked at a station or locked with its cable at an e-station, an approved public bike rack, or another public bike rack, light pole, signpost or retired parking meter within the service area. Based on this, an electric bike ride with no end station name is a ride that ended outside a Divvy station dock and is still a valid ride. This matches the data: 99.73% of the rows with missing station names are electric bike rides, and their coordinates are recorded only to two decimal places. <br>  4. Excluding these rows only from Q5 barely changes the member share (64.37% of all rides vs. 64.79%), but lowers the electric bike share from 68.68% to 60.38%.  |   03_investigate.sql 4-1, 4-2, 4-3, 4-4, 4-7, 4-8 <br> 02_profile.sql [8]  |
|  Station IDs and names do not map one-to-one  |  56 IDs with more than one name   <br>  67 names with more than one ID  |   No correction at the cleaning stage. <br> Trim spaces only.  |   The mismatches have several different causes (renamed stations, numbered suffixes, re-issued IDs), so no single simple rule fixes them. Their effect will be checked after implementing the analysis of Q5 |  02_profile.sql [5] <br> 03_investigate.sql 5-1, 5-2  |

**Limitations** : 
1. Q5 excludes 30.70% of electric bike rides , so electric bikes make up a smaller share of the rides used in Q5 (60.38%) than of all rides (68.68%). 
2. Station names and IDs are not fully consistent, which can split or merge a small number of stations in Q5.

**Impact Check**: <br>
After applying all cleaning rules, 166,578 rows (2.76% of the raw data) are removed. Members and casual riders lose a similar number of rides (84,217 and 82,361), but casual rides see a higher drop rate (3.83% vs. 2.17%) since their overall volume is smaller. The share of casual rides barely moves, going from 35.63% to 35.23%. <br>
Median ride duration goes up slightly for both groups (casual from 11.06 to 11.48 minutes, member from 8.58 to 8.75), which widens the gap between them from 2.48 to 2.73 minutes. Meanwhile, the casual mean drops sharply from 21.25 to 18.90 minutes. This is mainly because almost all of the 24-plus-hour rides we filtered out were casual trips. This shows how easily outliers distort the mean, making the median a much more reliable metric for Q2. Most importantly, cleaning the data doesn't change the comparison between members and casual riders.


## 4. Row Reconciliation

| Step | Rows removed | Rows remaining |
|---|---|---|
| Raw data | – | 6,037,968 |
| Remove duplicated rides | 35 | 6,037,933 |
| Remove rides with negative or zero duration | 29 | 6,037,904 |
| Remove rides shorter than 60 seconds | 160,902 | 5,877,002 |
| Remove rides longer than 24 hours | 5,334 <br> (7 of these rides were duplicates and were already removed before) | 5,871,668 | 
| Remove rides with no end coordinates | 278 | 5,871,390 |