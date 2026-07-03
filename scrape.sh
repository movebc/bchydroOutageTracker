#!/bin/bash
set -o errexit

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SCRAPE_ID=$(date +%s)
DATA_DIR="/tmp/bchydroScrapes/$SCRAPE_ID"

mkdir -p $DATA_DIR

SCRAPE_TIME=$(date -Iseconds)

curl -A movebc-bchydroOutageTracker/1.0 https://www.bchydro.com/power-outages/app/outages-list-data-current.json | jq . > $DATA_DIR/current.json
curl -A movebc-bchydroOutageTracker/1.0 https://www.bchydro.com/power-outages/app/outages-list-data-restored_14_days.json | jq . > $DATA_DIR/restored.json
curl -A movebc-bchydroOutageTracker/1.0 https://www.bchydro.com/power-outages/app/outages-list-data-planned.json | jq . > $DATA_DIR/planned.json

psql -v bch_scrape_timestamp=$SCRAPE_TIME -v bch_scrape_datadir=$DATA_DIR -f $SCRIPT_DIR/handleScrape.sql

rm -rf $DATA_DIR
