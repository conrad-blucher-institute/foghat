#!/usr/bin/env bash

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/ghrsst-l4

# The HREF archive has yesterday and today's files available, so try
# to download all of the ones we want w/in that range
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/ghrsst-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR  $ARCHIVE_DIR

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
echo "?downloading GHRSST Level 4 files from $1 ($year1$doy1) to $2 ($year2$doy2) on $now"  >>$LOG_FILE

# Generate file w/ URL globs (*.nc) for all the days we're interested in
count=0
y=$year1
d=$doy1
url_file=`mktemp --suffix=.${TODAY}-ghrsst_urls`
# Loop conditionals in arithmetic context
while (( y < year2 )) || (( y == year2 && d <= doy2 ))
do
    printf -v day '%03d' $d
    echo "ftp://ftp.nodc.noaa.gov/pub/data.nodc/ghrsst/GDS2/L4/GLOB/JPL/MUR/v4.1/$y/$day/*.nc" >>$url_file
    d=$((d + 1))
    # Handle day overflow.  366 b/c leap years, wget will fail on non-leap years
    if (( d > 366 ))
    then
        d=1
        y=$((y + 1))
    fi
    count=$((count + 1 ))
done

# TODO  Put files from different years in year-specific directories?
#       I'll have to change up the loop/downloading to do that :\

# Download the files
echo "?Attempting to download $count files (days) w/ URLs contained in $url_file" >>$LOG_FILE
/usr/bin/wget -nv --no-parent --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES --limit-rate=10m --wait=5 --timestamping -r -l 1 --append-output=$LOG_FILE --directory-prefix=$ARCHIVE_DIR -nd --input-file=$url_file

# Clean up temp file
rm $url_file
