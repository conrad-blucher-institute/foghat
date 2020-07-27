#!/usr/bin/env bash

# Extract probabilistic visibility predictions from NOMADS HREF dataset
# Mostly cut and paste, Q&D modification of maps_input.sh

# Bounding box for Hamid's DL NN
LON_LAT='-98.01:-94.20 25.4:28.85'

# Build a single regex w/ all the predictors at all the levels we want
MATCH_RE=":VIS:surface:"

# ---8<---  ---8<---  ---8<---  wgrib2 vars above  ---8<---  ---8<---  ---8<---

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_INPUT_DIR" || -z "$FOGHAT_EXE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

# Archive directory layout needs to match values in any other files
HREF_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-href

OUTPUT_DIR=$FOGHAT_INPUT_DIR/href-vis
TODAY=`date -u '+%Y%m%d'`
# Include PID in log filename in case multiple instances of this process are running simultaneously
LOG_FILE="$FOGHAT_LOG_DIR/href_vis-$TODAY-$$.log"

mkdir -p "$FOGHAT_LOG_DIR"  "$OUTPUT_DIR"

# Log brief error messages to notes file (e.g. missing days/data) for
# NetCDF data consumers
note() {
    local when=$1
    local msg=$2

    local year=`date -d "$when" '+%Y'`
    local fn="$OUTPUT_DIR/href-vis-notes-$year.txt"
    echo $msg >>"$fn"
}

process_grib_file() {
    local filename=$1

    # Restructure filename at this step in preparation for output name
    # (and to match maps processed data filenames)
    #
    # E.g., href.t00z.conus.prob.f09.20180204.grib2  →  href_vis_20180204_0000_009_check.nc
    local rename=`basename $filename | sed -E 's/^href\.t([0-9]{2})z\.conus\.prob\.f([0-9]{2})\.([0-9]{8})\.grib2/href_vis_\3_\100_0\2/;' `
    if [[ -z "$rename" ]]
    then
        echo "?Couldn't parse file $filename, skipping"
        return 1
    fi

    local unsorted=${rename}_raw.grb2
    local netcdf=${rename}_check.nc

    # Clip out the variables and levels we want w/in the desired bounding box
    wgrib2 $FOGHAT_WGRIB_OPTS $filename -set_grib_type c2 -match "$MATCH_RE" -small_grib $LON_LAT $unsorted >/dev/null

    # Make sure temporary GRIB file exists _and_ has content before continuing
    local size=`stat -c '%s' $unsorted 2>/dev/null || echo 0`
    if [[ ! -e "$unsorted" || $size -le 69 ]]
    then
        echo "?Error(s) occurred when trying to process $filename GRIB file, skipping"
        return
    fi

    # Convert to NetCDF
    #
    # Have to use extended names option (-set_ext_name 1) b/c variable and
    # level ( :VIS:surface: )  is not unique on its own.
    wgrib2 -set_ext_name 1 $FOGHAT_WGRIB_OPTS $unsorted -netcdf $netcdf >/dev/null
}


# Process all forecast hours files in a given date HREF directory
process_day() {
    local when=$1

    local start_t=`date '+%s'`

    # TODO  I think I _just_ need combined $ymd, no need need to split it
    local ymd=`date -d "$when" '+%Y %m%d'`
    read year md <<<$ymd                # year, month+day

    # Process HREF grib files for today
    local count=0
    for fn in $HREF_ARCHIVE_DIR/$year$md/href.t??z.conus.prob.f??.$year$md.grib2
    #for fn in $HREF_ARCHIVE_DIR/$year/$year$md/href.t${mc}z.conus.prob.f??.$year$md.grib2
    do
        process_grib_file $fn 1>&2
        count=$((count + 1))
    done

    local delta_t=$((`date '+%s'` - start_t))
    echo "?$count forecast hour files processed from $year$md in $delta_t seconds" 1>&2

    # Count should be either 72 (0, 12 model cycles) or 144 (0, 6, 12, 18)
    if [[ $count -ne 72 && $count -ne 144 ]]
    then
        echo "?Only saw $count grib file(s) when processing $year$md NOMADS HREF files, expected 72 or 144." 1>&2
        note "$when" "($year$md) Expected 72 or 144 grib files when processing HREF day $year$md but only saw $count "
    fi

    # Copy resulting visibility files to destination directory for given day
    local output_subdir=`date -d "$when" '+%Y/%Y%j'`
    local dest_path="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$dest_path"
    cp href_vis_$year*_check.nc "$dest_path"
}


# Convert from julian/ordinal day to YYYY-MM-DD for easy conversion by date (1)
#
# Code from https://superuser.com/a/232106/412259
jul2ymd () {
    date -d "$1-01-01 +$2 days -1 day" "+%Y-%m-%d";
}

seconds2hms () {
    local seconds=$1
    hour=$((seconds/3600))
    min=$(( (seconds % 3600) / 60))
    sec=$((seconds % 60))
    printf '%02d:%02d:%02d' $hour $min $sec
}

# Print usage and die
usage () {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage: $zero [-p] <start_date> <end_date>

Options:
  -p            Preserve intermediate files (debug only)

E.g., $zero 2018-11-01 2018-11-30

Both dates are inclusive.  Full list of calendar date formats supported at
<https://www.gnu.org/software/coreutils/manual/html_node/Calendar-date-items.html>
EndOfUsage
    exit
}

# Parse command line options
while getopts "c:hnp" OPTION; do
    case $OPTION in
    h)
        usage
        ;;
    p)
        PRESERVE=1
        ;;
    *)
        echo "Incorrect option ($OPTION) provided"
        exit 1
        ;;
    esac
done
# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
shift $((OPTIND -1))

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
[[ "$year1" -gt "$year2" ]] && echo "?ensure starting date ($year1,$doy1) is before end date ($year2,$doy2)" 1>&2 && usage
[[ "$year1" -eq "$year2" && "$doy1" -gt "$doy2" ]] && echo  "?ensure starting date ($year1,$doy1) is before end date ($year2,$doy2)" 1>&2 && usage

# Ensure (process-specific) local node storage for all temporary files
if [ -n "$TMPDIR" ]
then
    mkdir -p $TMPDIR
fi
TMP_DIR=`mktemp -d --suffix=.${TODAY}-href_vis`

now=`date`
echo "?generating HREF probabilistic [visibility] data from $1 ($year1, day $doy1) to $2 ($year2, day $doy2) on $now" >>"$LOG_FILE"

# Track time spent processing _all_ requested days and forecast hours
start_t=`date '+%s'`

pushd $PWD >/dev/null
cd $TMP_DIR

count=0
y=$year1
d=$doy1
# Loop conditionals in arithmetic context
while (( y < year2 )) || (( y == year2 && d <= doy2 ))
do
    # A bit of extra work but makes process_day argument cleaner
    when=`jul2ymd "$y" "$d"`
    # Not leap year check: skip date that doesn't fall in current year $y
    if [ ${when:0:4} -eq "$y" ]
    then
        process_day $when 2>>"$LOG_FILE"

        # Remove files from temporary directory so we don't fill up disk
        [[ ! $PRESERVE ]] && rm *.nc *.grb2 2>/dev/null
    fi

    d=$((d + 1))
    # Handle day overflow.  366 b/c leap years
    if (( d > 366 ))
    then
        d=1
        y=$((y + 1))
    fi
    count=$((count + 1 ))
done

popd >/dev/null

delta_t=$((`date '+%s'` - start_t))
elapsed=$(seconds2hms $delta_t)
echo "?processed $count day(s) of data in $elapsed time ($delta_t seconds)" >>"$LOG_FILE"

# Remove temporary directory (but should already be empty)
if [[ ! $PRESERVE ]]
then
    echo "?removing temporary directory, $TMP_DIR" >>"$LOG_FILE"
    rm -r $TMP_DIR
else
    echo "(*) →  leaving files in temporary directory $TMP_DIR  ← (*)" >>"$LOG_FILE"
fi
