# Airflow image with everything the pipeline needs.
# The course's 03_Airflow example installs packages with _PIP_ADDITIONAL_REQUIREMENTS, but dbt's
# dependencies clash with Airflow's, and that variable reinstalls on every container start.
# So, like the course's 06_dbt example, we build a small image instead:
#   - Airflow's own environment gets the packages the DAG tasks import (Postgres provider,
#     kagglehub, duckdb), installed against Airflow's constraint file so Airflow is not broken.
#   - dbt gets its own virtual environment (/home/airflow/dbt_venv), called from a BashOperator.

ARG AIRFLOW_VERSION=2.8.1
FROM apache/airflow:${AIRFLOW_VERSION}-python3.11

ARG AIRFLOW_VERSION=2.8.1
ARG DUCKDB_VERSION=1.3.2

# Packages for the DAG tasks (download from Kaggle, load into Postgres)
RUN pip install --no-cache-dir \
        "apache-airflow==${AIRFLOW_VERSION}" \
        apache-airflow-providers-postgres \
        "kagglehub==0.3.12" \
        --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-3.11.txt"

# duckdb is installed separately, without Airflow's constraint file: that file pins the old
# duckdb 0.9.2, but dbt-duckdb needs the same newer version as this environment (they share
# the postgres extension). duckdb has no Python dependencies, so this cannot break Airflow.
RUN pip install --no-cache-dir "duckdb==${DUCKDB_VERSION}"

# dbt in a separate virtual environment; the same duckdb version as above.
# PIP_USER=false: the Airflow image sets PIP_USER=true (install into ~/.local), which pip
# refuses inside a virtual environment.
RUN python -m venv /home/airflow/dbt_venv \
    && PIP_USER=false /home/airflow/dbt_venv/bin/pip install --no-cache-dir \
        "dbt-core==1.10.23" \
        "dbt-duckdb==1.9.6" \
        "duckdb==${DUCKDB_VERSION}"

# DuckDB's postgres extension is downloaded once at build time, so the containers do not need
# to fetch it at run time. Both environments use the same duckdb version and share the
# extension folder (~/.duckdb/extensions).
RUN python -c "import duckdb; duckdb.sql('INSTALL postgres')"

ENV DBT_BIN=/home/airflow/dbt_venv/bin/dbt
