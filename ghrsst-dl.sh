#!/usr/bin/env bash

# Group for High Resolution Sea Surface Temperature (GHRSST) Level 4 sea surface temperature analysis
# version 4 Multiscale Ultrahigh Resolution (MUR) L4 analysis
# AKA "MUR dataset"
# FMI https://podaac.jpl.nasa.gov/dataset/MUR-JPL-L4-GLOB-v4.1

# To download MUR data from NASA's Earthdata system, you need to:
#
# 1. Register an Earthdata login (if you don't have one already):
#    https://urs.earthdata.nasa.gov/profile
#
# 2. Follow the instructions to setup your ~/.netrc file for wget:
#    https://www.opendap.org/documentation/tutorials/ClientAuthentication.html#_wget

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_COOKIES" ]]
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
(( $year1 > $year2 )) && echo "?ensure starting date ($year1$doy1) is before end date ($year2$doy2)" 1>&2 && usage
(( $year1 == $year2 && $doy1 > $doy2 )) && echo  "?ensure starting date ($year1$doy1) is before end date ($year2$doy2)" 1>&2 && usage

# Make sure cookies file is private (b/c Earthdata session cookie)
chmod 600 $FOGHAT_COOKIES

now=`date`
echo "?downloading GHRSST Level 4 files from $1 ($year1,$doy1) to $2 ($year2,$doy2) on $now"  >>$LOG_FILE

# Generate file w/ URL globs (*.nc) for all the days we're interested in
count=0
y=$year1
d=$doy1
url_file=`mktemp --suffix=.${TODAY}-ghrsst_urls`
# Loop conditionals in arithmetic context
#
# XXX  There will be errors/failure w/ julian day 366 for non-leap years, but should otherwise work
while (( y < year2 )) || (( y == year2 && d <= doy2 ))
do
    ymd=`jul2ymd "$y" "$d"`
    printf -v day '%03d' $d
    # Use OPeNDAP server b/c regular HTTP/FTP _don't_ have a complete copy of the data archive (for some reason)
    #echo "https://podaac-opendap.jpl.nasa.gov/opendap/hyrax/allData/ghrsst/data/GDS2/L4/GLOB/JPL/MUR/v4.1/$y/$day/${ymd}090000-JPL-L4_GHRSST-SSTfnd-MUR-GLOB-v02.0-fv04.1.nc" >>$url_file
    # New NASA Earthdata d/l URL/system operational as of sometime in 2020?
    echo "https://archive.podaac.earthdata.nasa.gov/podaac-ops-cumulus-protected/MUR-JPL-L4-GLOB-v4.1/${ymd}090000-JPL-L4_GHRSST-SSTfnd-MUR-GLOB-v02.0-fv04.1.nc" >>$url_file
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
/usr/bin/wget -nv --load-cookies $FOGHAT_COOKIES --save-cookies $FOGHAT_COOKIES --keep-session-cookie $FOGHAT_WGET_OPTIONS --timestamping --append-output=$LOG_FILE --directory-prefix=$ARCHIVE_DIR --input-file=$url_file

# TODO  Move downloaded MUR files into correct year directory under MUR archive?  Limit to basenames from $url_file in case of parallel runs?

# Clean up temp file
rm $url_file
