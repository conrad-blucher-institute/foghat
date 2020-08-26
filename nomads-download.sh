#!/usr/bin/env bash

# Download HREF probability output (all probabilities; including
# visibility) on a daily basis from NOMADS (NOAA Operational Model
# Archive and Distribution System)
#
# https://nomads.ncep.noaa.gov/txt_descriptions/HREF_doc.shtml

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

# Kluge check for stale NFS filehandles before processing
# This is an issue when HPC storage is taken offline for maintenance and occasionally at other times
if [[ -n `ls $FOGHAT_LOG_DIR  $FOGHAT_ARCHIVE_DIR 2>&1 | grep 'Stale file handle'` ]]
then
    echo "¿ Is HPC research storage offline ?" 1>&2
    echo "?Stale file handle at $FOGHAT_LOG_DIR and/or $FOGHAT_ARCHIVE_DIR, giving up" 1>&2
    exit 1
fi

mkdir -p $FOGHAT_LOG_DIR  $FOGHAT_ARCHIVE_DIR


# Generate all possible HREF files for a given date (yyyymmdd)
generate_href_urls () {
    local date=$1

    # Generate file w/ all the URLs [we want] for the given day
    local base_url="https://nomads.ncep.noaa.gov/pub/data/nccf/com/hiresw/prod/href.$date/ensprod";

    local count=0
    for t in 00 06 12 18
    do
        run="t${t}z"
        for hr in {1..36}
        do
            printf -v forecast 'f%02d' $hr
            fn="href.${run}.conus.prob.${forecast}.grib2"
            echo "$base_url/$fn"
            count=$((count + 1))
        done
    done
}

# Generate file w/ all possible SREF URLs [we want] for the given day
generate_sref_urls () {
    local date=$1

    # Since we want each set of daily files to land in a separate directory,
    # I'm only generating one day at a time, even though it's 4 or 8 files :|
    local count=0
    for cc in 03 09 15 21
    do
        local base_url="https://nomads.ncep.noaa.gov/pub/data/nccf/com/sref/prod/sref.$date/$cc/ensprod"
        echo "$base_url/sref.t${cc}z.pgrb132.prob_3hrly.grib2"
        echo "$base_url/sref.t${cc}z.pgrb132.prob_3hrly.grib2.idx"
        count=$((count + 2))
    done
}

# Download all URLs passed in as stdin to specified destination path
download_urls () {
    local dest_path=$1
    local log_fqpn=$2

    mkdir -p $dest_path
    # Monitor and log time of all downloads
    local start=`date '+%s'`
    echo "?downloading URLs into $dest_path" >>$log_fqpn
    /usr/bin/wget -nv --no-parent --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES --limit-rate=10m --wait=5 --timestamping --append-output=$log_fqpn --directory-prefix=$dest_path --input-file=-
    local end=`date '+%s'`
    local delta=$((end - start))
    printf -v mmss '%d:%02d' $((delta/60)) $((delta % 60))
    echo "?_Attempted to_ download data files (into $dest_path) in $delta seconds ($mmss)" >>$log_fqpn
}

# Add date to filename using hard links here b/c straightforward renaming
# will cause wget to download _everything_ again when it is re-run
rename_w_date() {
    local archive_fqpn=$1

    if [ ! -d "$archive_fqpn" ]
    then
        echo "?Looks like there aren't any files in $archive_fqpn yet, skipping"
        return
    fi

    cd $archive_fqpn
    echo "?In $archive_fqpn:"
    for i in *
    do
        j=`echo $i | sed -r "s/\.(f[0-3][0-9]|prob_3hrly)\.grib2/.\1.${date}.grib2/;"`
        if [[ "$j" != '*' && ! -e "$j" ]]
        then
            echo "  • Link $i → $j"
            ln $i $j
        fi
    done
    cd - >/dev/null
}


# Print usage and die
usage () {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage: $zero <mode>
Download latest available HREF or SREF data from NOMADS

<mode> must be one of { href, sref }

E.g., $zero href
EndOfUsage
    exit
}

[[ -z "$1" ]] && usage

MODE=$1
[[ ! "$MODE" =~ ^href|sref$ ]] && {
    echo -e "?Invalid mode specified ($MODE).  Must be one of: href, sref\n"
    usage
}


TODAY=`date -u '+%Y%m%d'`
YESTERDAY=`date -u '+%Y%m%d' -d 'yesterday'`

# XXX  If we add another data set/model, might want to refactor this

if [[ "$MODE" == 'href' ]]
then
    # The HREF archive has yesterday and today's files available, so
    # try to download all of the ones we want w/in that range

    LOG_FILE="$FOGHAT_LOG_DIR/nomads-href-$TODAY.log"
    ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-href
    for date in $YESTERDAY $TODAY
    do
        year="${date:0:4}"
        DEST_PATH="$ARCHIVE_DIR/$year/$date"
        generate_href_urls $date | download_urls $DEST_PATH $LOG_FILE
        rename_w_date $DEST_PATH >>$LOG_FILE
    done

elif [[ "$MODE" == 'sref' ]]
then
    LOG_FILE="$FOGHAT_LOG_DIR/nomads-sref-$TODAY.log"
    ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-sref
    # Kluge, but much simpler/easier than date loop logic :\
    daysago2=`date -u '+%Y%m%d' -d '2 days ago'`
    daysago3=`date -u '+%Y%m%d' -d '3 days ago'`
    daysago4=`date -u '+%Y%m%d' -d '4 days ago'`
    daysago5=`date -u '+%Y%m%d' -d '5 days ago'`
    # 6 days of SREF data are available
    for date in $daysago5 $daysago4 $daysago3 $daysago2 $YESTERDAY $TODAY
    do
        year="${date:0:4}"
        DEST_PATH="$ARCHIVE_DIR/$year/$date"
        generate_sref_urls $date | download_urls $DEST_PATH $LOG_FILE
        rename_w_date $DEST_PATH >>$LOG_FILE
    done
else
    usage
fi

