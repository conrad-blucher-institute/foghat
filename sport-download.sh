#!/usr/bin/env bash

# Download latest sea surface temperature (SST) data from NASA's SPoRT model running 30-day archive
URL='https://geo.nsstc.nasa.gov/SPoRT/sst/northHemisphere/grib2/'

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/sport-sst
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/sport-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR  $ARCHIVE_DIR

START=`date '+%s'`
echo "?downloading latest data from $URL" >>$LOG_FILE
/usr/bin/wget -nv --no-parent -r --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES --limit-rate=5m --wait=5 --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$ARCHIVE_DIR  $URL
END=`date '+%s'`
DELTA=$((END - START))
printf -v MMSS '%d:%02d' $((delta/60)) $((delta % 60))
echo "?downloaded data files in $DELTA seconds ($MMSS) " >>$LOG_FILE

