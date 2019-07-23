#!/usr/bin/env bash

# Download latest sea surface temperature (SST) data from NASA's SPoRT model running 30-day archive
URL='https://geo.nsstc.nasa.gov/SPoRT/sst/northHemisphere/grib2/'

SPORT_BASE=$HOME/sport-sst
LOG_DIR=$SPORT_BASE/logs
ARCHIVE_DIR=$SPORT_BASE/archive
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$LOG_DIR/sport-$TODAY.log"

# wget options
COOKIES_FILE='.cookies'

mkdir -p $LOG_DIR $ARCHIVE_DIR

START=`date '+%s'`
echo "?downloading latest data from $URL" >>$LOG_FILE
/usr/bin/wget -nv --no-parent -r --limit-rate=5m --wait=5 --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$ARCHIVE_DIR  $URL
END=`date '+%s'`
DELTA=$((END - START))
echo "?downloaded data files in $DELTA seconds" >>$LOG_FILE

