#!/usr/bin/env bash

# Download archival NAM data from a NOAA AIRS order

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

usage () {
    local zero=`basename $0`
    echo "$zero <email_id> <order_id> <url>"
    exit
}

if [[ -z "$1" || -z "$2" || -z "$3" ]]
then
    usage
fi
EMAIL_ID=$1
ORDER_ID=$2
URL=$3

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nam-grib
TMP_DIR=$FOGHAT_BASE/tmp
DOWNLOAD_TARGET=$TMP_DIR/$ORDER_ID
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/order_$ORDER_ID-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR $ARCHIVE_DIR  $TMP_DIR

# See https://www.ncdc.noaa.gov/has/has.orderguide for suggestions
# TODO  Reject 'index.html?C=*' variants and robots.txt files
/usr/bin/wget -erobots=off -nv --no-parent -r --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$DOWNLOAD_TARGET  $URL

# TODO  Strip file list from index.html  [assuming it was downloaded] and save as file_list.txt
# TODO  Move files to correct directory (somewhere under $ARCHIVE_DIR)
# TODO  Unpack files?!
# TODO  Trigger email move to "processed" folder
