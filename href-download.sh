#!/usr/bin/env bash

# Download HREF probability output (all probabilities; including
# visibility) on a daily basis from NOMADS (NOAA Operational Model
# Archive and Distribution System)

NOMADS_BASE=$HOME/nomads-href
LOG_DIR=$NOMADS_BASE/logs
ARCHIVE_DIR=$NOMADS_BASE/archive

# wget options
COOKIES_FILE='.cookies'

# The HREF archive has yesterday and today's files available, so try
# to download all of the ones we want w/in that range
TODAY=`date -u '+%Y%m%d'`
YESTERDAY=`date -u '+%Y%m%d' -d 'yesterday'`
LOG_FILE="$LOG_DIR/href-$TODAY.log"

mkdir -p $LOG_DIR $ARCHIVE_DIR

# Download HREF files for a given date (yyyymmdd)
download_href () {
    local date=$1

    # Generate file w/ all the URLs [we want] for the given day
    local base_url="https://nomads.ncep.noaa.gov/pub/data/nccf/com/hiresw/prod/href.$date/ensprod";
    local url_file=`mktemp --suffix=.${date}-href_urls`
    local count=0
    for t in 00 06 12 18
    do
        run="t${t}z"
        for hr in {1..36}
        do
            printf -v forecast 'f%02d' $hr
            fn="href.${run}.conus.prob.${forecast}.grib2"
            echo "$base_url/$fn" >>$url_file
            count=$((count + 1))
        done
    done

    # Monitor and log time of all downloads
    local start=`date '+%s'`
    echo "?downloading URLs for $date contained in $url_file" >>$LOG_FILE
    /usr/bin/wget -nv --no-parent --save-cookies $COOKIES_FILE --limit-rate=5m --wait=10 --timestamping --append-output=$LOG_FILE --directory-prefix=$ARCHIVE_DIR/$date --input-file=$url_file
    local end=`date '+%s'`
    local delta=$((end - start))
    echo "?downloaded $count data files (from $url_file) for $date in $delta seconds" >>$LOG_FILE

    # Add date to filename using hard links here b/c straightforward
    # renaming will cause wget to download _everything_ again when
    # it is re-run
    cd $ARCHIVE_DIR/$date
    echo "?In $ARCHIVE_DIR/$date:" >>$LOG_FILE
    for i in *
    do
        j=`echo $i | sed "s/\.f[0-3][0-9]\.grib2$/.${date}.grib2/;"`
        if [ ! -e $j ]
        then
            echo "  • Link $i → $j" >>$LOG_FILE
            ln $i $j
        fi
    done
    cd - >/dev/null

    # Clean up after yourself
    rm $url_file
}


download_href $YESTERDAY
download_href $TODAY
