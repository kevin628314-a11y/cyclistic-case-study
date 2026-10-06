# Cyclistic Bike-Share Case Study

This is my capstone project for the Google Data Analytics Certificate. I analyze 12 months of Divvy trip data to find how annual members and casual riders use bikes differently, and how casual riders could be converted into members.

![All start stations, casual share of rides](figures/q5_map_all_stations.png)

 *Each circle is a start station. Color: casual riders' share of rides (orange is higher than the overall 35.13%, blue is lower). Size: total rides.*

## Introduction

Cyclistic is a fictional bike-share company in Chicago, and the data in this case study comes from Divvy, Chicago's real bike-share system. Cyclistic provides a fleet of bicycles for public use throughout the city. The company offers three types of plans: single-ride passes, full-day passes, and annual memberships. Customers who purchase single-ride or full-day passes are referred to as casual riders, while those who buy annual memberships are annual members.

The director of marketing, Lily Moreno, plans to launch a new marketing initiative to grow the business. According to the finance analysts, annual members are much more profitable than casual riders. Therefore, rather than continuing to build broad brand awareness, Moreno wants to encourage existing casual riders to become annual members.

To achieve this goal, the analyst team needs to examine historical trip data and identify the differences in usage between annual members and casual riders. By understanding how casual riders use the bikes, the team can develop strategies to encourage them to purchase annual memberships.

## Business task

Identify how annual members and casual riders use Cyclistic bikes differently, and determine which casual-rider usage patterns point to opportunities for converting them into annual members. These findings will help Moreno's marketing team design a targeted campaign for existing casual riders.

**Business questions:**
1. How do annual members and casual riders use Cyclistic bikes differently?
2. How can Cyclistic convert casual riders into annual members?

## Approach

To answer the business questions, we break them down into five analysis questions that can be answered with the trip data. Q1 to Q5 answer business question 1 directly, while business question 2 is answered by the suggestions based on their findings.

**Analysis questions:**

| Question | Rides used |
|---|---|
| Q1 How many rides does each group take? | All cleaned rides (5,871,390) |
| Q2 How long do they ride? | All cleaned rides |
| Q3 When do they start riding? | All cleaned rides |
| Q4 Which bike type do they choose? | All cleaned rides |
| Q5 What is the difference in starting stations between casual riders and members? | Rides with a start station name (4,690,815) |

1. **Q1 to Q4 compare the overall behavior of the two groups:** ride counts, ride duration, start hour, and bike type.
2. **Q5 looks at where each group starts its rides.** Q1 to Q4 only show behavior differences between the two groups. They cannot tell us where marketing should be placed, or which locations to target. Q5 makes the marketing campaigns more specific.
3. **Q5 starts with all 1,955 start stations, then takes a closer look at the top 20.** The all-stations map shows the overall spatial pattern, but there are too many stations to compare specific places. The top 20 stations for each group show which high-volume stations drive the pattern.
4. **The findings from Q1 to Q5 are turned into suggestions** for what to offer, when to reach casual riders, and where to reach them.

## Key findings

This analysis uses Divvy trip data from August 2025 to July 2026 (5,871,390 cleaned rides) to understand how members and casual riders use the bikes differently and how Cyclistic can convert casual riders into members.

1. **Members take more rides:** Members account for 64.77% of all rides, about 1.84 times the share of casual riders (35.23%).
2. **The two groups have different riding patterns:** Casual riders take longer rides (median 11.48 vs. 8.75 minutes), while members have a higher share of rides during commuting hours (from 7:00 to 9:00: 17.54% vs. 9.50%). Casual riders have a higher share of rides from 10:00 to 15:00 (37.01% vs. 30.93%).
3. **Bike type shows little difference:** Electric bikes account for about two-thirds of rides in both groups.
4. **Riding locations differ:** Lakefront stations have many rides and a high share of casual rides, while stations in business districts (the Loop, West Loop, and River North) have a higher share of member rides.
5. **Suggestions for conversion:** We suggest offering membership benefits based on ride duration, reaching casual riders during the middle of the day, and using ads or on-site events at lakefront stations.

**Note:** We do not have rider-level data, so these findings and suggestions are based only on ride records and have not been tested.

Full findings, charts, and limitations: [analysis_finding.md](docs/analysis_finding.md)

## Tools

- DuckDB (SQL): import, cleaning, and one summary table per question
- Python (pandas, matplotlib) in a Jupyter notebook: charts for Q1 to Q4
- Tableau Public: maps for Q5 ([All start stations](https://public.tableau.com/app/profile/kevin.lin4959/viz/Allstartstationscasualshareofrides/1), [Top 20 start stations](https://public.tableau.com/app/profile/kevin.lin4959/viz/Cyclist-case-study_17905846497750/1_1))

## Repository structure

| Path | Content |
|---|---|
| `sql/` | `01_import.sql` to `05_analysis.sql`, run in order |
| `notebooks/analysis.ipynb` | Charts for Q1 to Q4 |
| `docs/cleaning_log.md` | Cleaning decisions |
| `docs/analysis_finding.md` | Findings, suggestions, and limitations |
| `figures/` | Charts and map screenshots |
| `data/processed/` | Station summaries exported for the Q5 maps |

## How to reproduce

Due to the restriction of the Divvy Data License Agreement, the raw data needs to be downloaded from the publisher's website. The following steps can reproduce the project:

1. Download the 12 monthly files from `202508-divvy-tripdata.zip` to `202607-divvy-tripdata.zip` at https://divvy-tripdata.s3.amazonaws.com/index.html, and unzip the CSV files into `data/raw/`.
2. Install the Python packages: `pip install -r requirements.txt`
3. From the project root, open the database with the DuckDB CLI (`duckdb data/divvy.duckdb`) and run the SQL files in order with `.read sql/01_import.sql` to `.read sql/05_analysis.sql`.
4. Quit the DuckDB CLI, then run `notebooks/analysis.ipynb`.

## Data source

Divvy trip data, https://divvy-tripdata.s3.amazonaws.com/index.html, made available by Motivate International Inc. under the [Divvy Data License Agreement](https://divvybikes.com/data-license-agreement).
