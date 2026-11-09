# Spotify Charts Warehouse

A dbt-powered data warehouse that turns daily Spotify Top-200 chart data into a clean, analytics-ready star schema. 
Enabling questions such as: 
*What's the hottest song in Estonia this week? Where is an artist strongest? Which labels dominated last quarter?*


## The idea in one minute

Spotify publishes a Top-200 chart for every country, every day - 
[Spotify Charts (Daily Updated)](https://www.kaggle.com/datasets/gonzalopezgil/spotify-charts-daily-updated). 
That's a lot of rows (almost 4 million song rows since January 2026) 
and the raw files are messy: songs have several URIs, the same artist sometimes appears twice on one day's chart,
labels go missing, and release dates are unreliable.

This project cleans all of that up in three steps and ends with a **star schema**:
three weekly fact tables surrounded by three dimension tables. Analysts query the star schema and never touch the raw data.

```
raw CSVs  ──►  staging  ──►  intermediate  ──►  marts and dims (star schema)
 (as-is)      (clean types)  (joins, keys,      (what you query)
                              metrics)
```


## How the project is organised

```
spotify_charts_pipeline/       # project 2: Main project
   README.md                   # project overview, documentation and instructions
   dags/                       # Airflow DAGs
   dbt_project/                # dbt models and transformations
   notebooks/                  # exploratory analysis and model prototypes
   sql/                        # updated SQL scripts

spotify_charts_outline/        # project 1: Archived
   tests/                      # tests
   demo_queries/               # example SQL queries
   DATA_DICTIONARY.md          # data definitions
   README.md                   # original project documentation

README.md                      # repository overview
```

