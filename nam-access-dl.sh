#!/usr/bin/env bash

# Download NAM-NMM data from NOAA's online data access links [1][2].  It
# appears they now keep the datasets online/available starting around
# middle of May 2020.
#
# I assume older forecast archives still have to be requested via AIRS
#
# [1] https://www.ncei.noaa.gov/products/weather-climate-models/north-american-mesoscale
#     I'm not _really_ sure what they call this particular service or if
#     it's available for more than the NAM-NMM dataset
#
# [2] E.g., https://www.ncei.noaa.gov/data/north-american-mesoscale-model/access/forecast/

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nam-grib
NOW=`date -u '+%Y%m%d_%H%M'`
# Include PID in [log] filename in case of parallel runs?
LOG_FILE="$FOGHAT_LOG_DIR/nam_access-$NOW-$$.log"

mkdir -p $FOGHAT_LOG_DIR  $ARCHIVE_DIR

# Convert from julian/ordinal day to YYYYMMDD b/c we need for the explicit filename URL to download via OPeNDAP server :\
#
# Code from https://superuser.com/a/232106/412259
jul2ymd () {
    date -d "$1-01-01 +$2 days -1 day" "+%Y%m%d";
}

# Print usage and die
usage () {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage: $zero <start_date> <end_date>

E.g., $zero 2018-11-01 2018-11-30

Both dates are inclusive.  Full list of calendar date formats supported at
<https://www.gnu.org/software/coreutils/manual/html_node/Calendar-date-items.html>
EndOfUsage
    exit
}

[[ -z "$1" || -z "$2" ]] && usage

date1=`date -d "$1" '+%Y %j'`
date2=`date -d "$2" '+%Y %j'`
# If empty, assume error when processing
[[ -z "$date1" || -z "$date2" ]] && usage

read year1 doy1 <<<$date1
read year2 doy2 <<<$date2

# Force decimal context b/c leading zeros will be interpreted as octal
# FMI see https://blog.famzah.net/2010/08/07/beware-of-leading-zeros-in-bash-numeric-variables/
doy1=$((10#$doy1))
doy2=$((10#$doy2))

# Sanity checks
[[ $year1 > $year2 ]] && echo "?ensure starting date ($year1$doy1) is before end date ($year2$doy2)" 1>&2 && usage
[[ $year1 == $year2 && $doy1 > $doy2 ]] && echo  "?ensure starting date ($year1$doy1) is before end date ($year2$doy2)" 1>&2 && usage

now=`date`
echo "?downloading NAM NMM/ANL data from $1 ($year1,$doy1) to $2 ($year2,$doy2) on $now"  >>$LOG_FILE

# Loop over all days we're interested in
count=0
y=$year1
d=$doy1

# Make [local disk] temporary path
TMP_DIR=$(mktemp -d --suffix=.${NOW}-nam_access)
# Temporary [file] index.html of NAM remote folder (per day)
TMP_INDEX=$(mktemp --suffix=.${NOW}-nam-index_html)

# Loop conditionals in arithmetic context
#
# XXX  There will be errors/failure w/ julian day 366 for non-leap years, but should otherwise work
while (( y < year2 )) || (( y == year2 && d <= doy2 ))
do
    ymd=`jul2ymd "$y" "$d"`             # YYYYMMDD
    printf -v day '%03d' $d             # day of year
    m=${ymd:4:2}                        # current month

    # We download both analysis and forecast data (as per original request)
    for target in 'nam' 'namanl'
    do
        # Both forecasts and analysis d/l and archive are handled the same, we just map URL directory (index) to a different tarfile prefix.  Either `nam` or `namanl`
        # Assume forecasts
        url="https://www.ncei.noaa.gov/data/north-american-mesoscale-model/access/forecast/$y$m/$ymd/"
        dest_path="$ARCHIVE_DIR/nmm/$y"
        # Downloading analysis instead?
        if [[ $target == 'namanl' ]]
        then
            url="https://www.ncei.noaa.gov/data/north-american-mesoscale-model/access/analysis/$y$m/$ymd/"
            dest_path="$ARCHIVE_DIR/anl/$y"
        fi
        # Make sure destination exists
        mkdir -p $dest_path

        # Nuke contents in index.html [cache]
        echo -n '' >$TMP_INDEX

        # Loop over each model cycle (0, 6, 12, 18).  Our [existing] output/archive is grouped that way
        for cycle in '00' '06' '12' '18'
        do
            # Day, target and cycle appropriate destination filename/path
            tarfile="${target}_218_$ymd$cycle.g2.tar"
            dest_fqpn="$dest_path/$tarfile"

            # Skip if day + model_cycle already been downloaded and archived
            if [[ -r $dest_fqpn ]]
            then
                echo "?Destination $tarfile already exists, skipping ($target, $ymd, $cycle)" >>$LOG_FILE
                continue
            fi

            # Download index.html [once] for day (I've had it take _minutes_)
            if [[ ! -s "$TMP_INDEX" ]]
            then
                echo "?Downloading directory list for $url" >>$LOG_FILE
                /usr/bin/wget -nv --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES $FOGHAT_WGET_OPTIONS --append-output=$LOG_FILE --output-document=$TMP_INDEX "$url"
	    fi

            # Generate appropriate list of md5sum.* and *.grb2 files (for desired model cycle) in remote directory (URL)
            file_list=$TMP_DIR/file_list.txt
            # Include md5sum file in every archive
            md5today="md5sum.$ymd"
            echo $md5today >$file_list
            # Only include grib files for current model cycle in d/l list
            grep -oiP '(?<=href=")(nam[^"]+\.grb2)(?=")' $TMP_INDEX | grep -F "${ymd}_$cycle" >>$file_list

            # Download the data
            echo "?Downloading $target data files for $ymd, cycle $cycle" >>$LOG_FILE
            /usr/bin/wget -nv --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES $FOGHAT_WGET_OPTIONS --timestamping --append-output=$LOG_FILE --directory-prefix=$TMP_DIR --base="$url" --input-file=$file_list

            # Filter md5sums file contents to just current model cycle (files we're downloading)
            grep -P "${ymd}_${cycle}00_\d+\.grb2$" $TMP_DIR/$md5today >$TMP_DIR/md5sum.tmp
            # TODO  Only replace $md5today file _if_ md5sum.tmp has contents (i.e., not empty)
            mv $TMP_DIR/md5sum.tmp $TMP_DIR/$md5today

            # TODO  Check md5sums?
            # If following md5sum command returns 0 (success), everything is OK
            #md5sum --quiet -c "$TMP_DIR/$md5today" && echo "?md5sums checked out" >>$LOG_FILE

            # Make correctly-named tar file out of data files we just downloaded.  Make tarball in that directory (local disk)
            file_count=$(ls -1 $TMP_DIR | wc --lines)
            # TODO  Do NOT generate tar file if no useful files are present in the directory.  E.g., only (empty) md5sum.* and file_list.txt files
            echo "?Tar'ring $file_count files into $tarfile" >>$LOG_FILE
            tar_fqpn="$TMP_DIR/$tarfile" # where we're making the tarfile
            tar --exclude='*.tar' -cf $tar_fqpn --directory=$TMP_DIR '.'

            # Move tarball to correct archive directory
            mv $tar_fqpn $dest_fqpn

            # Delete contents of temporary path (but not the path itself)
            rm $TMP_DIR/*
        done
    done                                # forecast / analysis

    # Go to next day
    d=$((d + 1))
    # Handle day overflow.  366 b/c leap years, wget will fail on non-leap years
    if (( d > 366 ))
    then
        d=1
        y=$((y + 1))
    fi
    count=$((count + 1 ))
done

# Clean up temporary directory and file(s)
rm -r $TMP_DIR
rm $TMP_INDEX