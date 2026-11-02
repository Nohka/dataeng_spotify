"""dbt transformations: builds and tests the warehouse from the raw Postgres tables.

    dbt_build

  * dbt_build   runs `dbt build` in the DuckDB warehouse, in dependency order: creates the silver
                models (stg, int) as views and the gold models (mart, dim) as tables, and runs
                every dbt test. dbt reads the raw tables straight from the raw Postgres database
                (attached as catalog "raw").

Triggered by the kaggle_to_raw DAG after a successful load, with the same start_date.
It can also be triggered on its own (e.g. after changing a model), which rebuilds the models
on the raw data that is already loaded.

Parameter (Trigger DAG w/ config): start_date (first chart date to analyse).
"""

import os
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.models.param import Param
from airflow.operators.bash import BashOperator

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"

default_args = {
    "owner": "airflow",
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}

with DAG(
    dag_id="dbt_transform",
    description="Build and test the dbt models (DuckDB warehouse) from the raw Postgres tables",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule=None,                     # started by kaggle_to_raw, or manually
    catchup=False,
    max_active_runs=1,                 # a DuckDB file accepts only one writer at a time
    default_args=default_args,
    params={
        "start_date": Param(os.environ.get("PIPELINE_START_DATE", "2025-01-01"), type="string",
                            format="date", description="First chart date to analyse"),
    },
    tags=["spotify", "dbt", "duckdb"],
) as dag:

    t_dbt = BashOperator(
        task_id="dbt_build",
        # dbt build = run all models + all tests, in dependency order.
        # DBT_BIN, DBT_PROFILES_DIR, DBT_TARGET_PATH and DBT_LOG_PATH come from the image / compose.yml.
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            "$DBT_BIN build --vars '{\"start_date\": \"{{ params.start_date }}\"}'"
        ),
        # The run fails with a lock error if DBeaver has the DuckDB file open.
        # Retrying a few times gives time to disconnect DBeaver before the run is marked failed.
        retries=3,
        retry_delay=timedelta(minutes=10),
    )
