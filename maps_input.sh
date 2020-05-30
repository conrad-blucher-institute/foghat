#!/usr/bin/env bash

# Generate Deep Learning Neural Net MapS fog input data for Hamid

# Bounding box for Hamid's MapS DL NN
LON_LAT='-98.01:-94.20 25.4:28.85'

# MUR SST ncks latitude/longitude filtering CLI options (should match above)
MUR_NCKS_ARGS='-d lat,25.24,29.0 -d lon,-98.01,-94.25'

# Build a single regex w/ all the predictors at all the levels we want
ATMOSPHERIC=':(TMP|RH|UGRD|VGRD|TKE|VVEL):(700|725|750|775|800|825|850|875|900|925|950|975) mb:'
ABOVE_GROUND=':(TMP|DPT|RH|UGRD|VGRD):(2|10) m above ground:'
SURFACE=':(FRICV|VIS|TMP):surface:'
# Mean sea level (pressure) is only used to calculate derived parameter(s)
UNIQUE=':MSLET:'
MATCH_RE="($ATMOSPHERIC|$ABOVE_GROUND|$SURFACE|$UNIQUE)"

# ---8<---  ---8<---  ---8<---  wgrib2 vars above  ---8<---  ---8<---  ---8<---

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_INPUT_DIR" || -z "$FOGHAT_EXE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

# Archive directory layout needs to match values in any other files
NMM_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nam-grib/nmm
MUR_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/ghrsst-l4

OUTPUT_DIR=$FOGHAT_INPUT_DIR/fog-maps   # XXX confusing naming
TODAY=`date -u '+%Y%m%d'`
# Include PID in log filename in case multiple instances of this process are running simultaneously
LOG_FILE="$FOGHAT_LOG_DIR/maps_input-$TODAY-$$.log"

mkdir -p "$FOGHAT_LOG_DIR"  "$OUTPUT_DIR"

# Log brief error messages to notes file (e.g. missing days/data) for
# NetCDF data consumers
note() {
    local when=$1
    local msg=$2

    local year=`date -d "$when" '+%Y'`
    local fn="$OUTPUT_DIR/processing-notes-$year.txt"
    echo $msg >>"$fn"
}

process_grib_file() {
    local filename=$1
    local noext=`echo $filename | sed 's/^nam_218/maps/; s/\.grb2//;'`
    local unsorted=${noext}_raw.grb2
    local sorted=${noext}_sorted.grb2
    local netcdf=${noext}_wip.nc
    local final_netcdf=${noext}_input.nc

    # Clip out the variables and levels we want w/in the desired bounding box
    wgrib2 $FOGHAT_WGRIB_OPTS $filename -set_grib_type c2 -match "$MATCH_RE" -small_grib $LON_LAT $unsorted >/dev/null

    # Reorder grib2 variables [predictors] as noted in Waylon's document
    wgrib2 $FOGHAT_WGRIB_OPTS $unsorted | $FOGHAT_EXE_DIR/grib2_inv_reorder.pl | wgrib2 $FOGHAT_WGRIB_OPTS -i $unsorted -set_grib_type c2 -grib_out $sorted >/dev/null

    # Make sure temporary GRIB file exists _and_ has content before continuing
    local size=`stat -c '%s' $sorted 2>/dev/null || echo 0`
    if [[ ! -e "$sorted" || $size -le 69 ]]
    then
        echo "?Error(s) occurred when trying to process $filename GRIB file, skipping" 1>&2
        return
    fi

    # Convert to NetCDF
    wgrib2 $FOGHAT_WGRIB_OPTS $sorted -netcdf $netcdf >/dev/null

    # Using variables in NetCDF file, add derived variables (in place)
    $FOGHAT_EXE_DIR/maps_derived.py $netcdf

    # Remove mean sea level pressure (surface pressure)  from NetCDF file, as per waylon
    ncks --no_alphabetize -O -x -v MSLET_meansealevel $netcdf $final_netcdf
}

# Process all forecast hours files in a given (date, model cycle) NAM tarfile
process_day_cycle() {
    local when=$1
    local cycle=$2

    local start_t=`date '+%s'`
    local ymd=`date -d "$when" '+%Y %m%d'`
    read year md <<<$ymd                # year, month+day
    printf -v mc '%02d' $cycle          # model cycle, formatted

    # For given date, cycle, build .tar filename
    local tarfile=$NMM_ARCHIVE_DIR/$year/nam_218_$year$md$mc.g2.tar
    echo "?Extracting forecast hour files from $tarfile ($year$md, $cycle)" 1>&2

    if [[ ! -e $tarfile ]]
    then
        note "$when" "($year$md, $cycle) Can't find source data grib tarfile ($tarfile), skipping"
        echo "?Can't find ($year$md, $cycle) grib tarfile, $tarfile " 1>&2
        return
    fi

    # Extract forecast hours 0-36 from (day, model cycle) grib tarfile
    # XXX  CLI testing made it seem I have to be _really_ specific w/ my file glob otherwise it matches unwanted files?!
    local EXPECTED_COUNT=37
    local grib_files=`tar xvf "$tarfile" --directory=$TMP_DIR --wildcards nam_218_$year${md}_${mc}00_0{[012][0-9],3[0-6]}.grb2`

    # Process NAM grib files
    local count=0
    for fn in $grib_files
    do
        # Check for errors/unavailable files ?
        process_grib_file $fn
        count=$((count + 1))
    done

    local delta_t=$((`date '+%s'` - start_t))
    echo "?$count forecast hour files processed from $tarfile in $delta_t seconds" 1>&2

    # Count should be 37 files, if not then log [somewhere else], [probably] discard?
    if [ $count -ne $EXPECTED_COUNT ]
    then
        echo "?Only saw $count .grb2 file(s) when processing ($year$md, $cycle) grib tarfile, expected $EXPECTED_COUNT.  Skipping model cycle file $tarfile " 1>&2
        note "$when" "($year$md, $cycle) Expected $EXPECTED_COUNT .grb2 files when processing model cycle but only saw $count.  Skipping model cycle"
        return
    fi

    # Copy resulting MapS input files to destination directory for given day
    local output_subdir=`date -d "$when" '+%Y/%Y%j'`
    local dest_path="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$dest_path"
    cp maps_$year*_input.nc "$dest_path"

    # TODO  ¿ Add CLI option to copy temporary (WIP) NetCDF files ± source [clipped/sorted] .grb2 files into destination directory for verification ?
}

crop_mur() {
    local when=$1

    # Ugh, feels like a lot of redundancy.  However, the goal is sufficing
    local murdate=`date -d "$when" '+%Y%m%d'`
    # XXX Obviously hoping the MUR SST filenames are consistent across the years
    local mur_fn="${murdate}090000-JPL-L4_GHRSST-SSTfnd-MUR-GLOB-v02.0-fv04.1.nc"
    local year=${murdate:0:4}
    local input_fqpn="$MUR_ARCHIVE_DIR/$year/$mur_fn"

    # Clip MUR_SST and dump output to destination directory for given day
    local output_subdir=`date -d "$when" '+%Y/%Y%j'`
    local dest_path="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$dest_path"
    local dest_fqpn="$dest_path/murs_${murdate}_0000_009_input.nc"

    # TODO ¿ Write output cropped MUR to local storage ($TMP_DIR?) _then_ copy to destination?
    echo "?Cropping $mur_fn" 1>&2
    ncks --no_alphabetize $MUR_NCKS_ARGS "$input_fqpn" -O "$dest_fqpn"
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
Usage: $zero [-p] [-c CYCLE] <start_date> <end_date>

Options:
  -n            No MUR SST cropping
  -p            Preserve intermediate files (debug only)
  -c CYCLE      Only calculate model cycle hour CYCLE (0, 6, 12, 18)

E.g., $zero 2018-11-01 2018-11-30

Both dates are inclusive.  Full list of calendar date formats supported at
<https://www.gnu.org/software/coreutils/manual/html_node/Calendar-date-items.html>
EndOfUsage
    exit
}

# Default is to crop MUR SST files
MUR_CROP=1

# Parse command line options
while getopts "c:hnp" OPTION; do
    case $OPTION in
    c)
        CYCLE=$OPTARG
        [[ ! $CYCLE =~ 0|6|12|18 ]] && {
            echo "Invalid model cycle specified ($OPTARG)"
            exit 1
        }
        ;;
    h)
        usage
        ;;
    n)
        MUR_CROP=
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

# If no specific model cycle specified, run all of them
[[ -n "$CYCLE" ]] || CYCLE="0 6 12 18"

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
TMP_DIR=`mktemp -d --suffix=.${TODAY}-maps_input`

now=`date`
echo "?generating MapS input data from $1 ($year1, day $doy1) to $2 ($year2, day $doy2) on $now" >>"$LOG_FILE"

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
    # A bit of extra work but makes process_day_cycle() arguments cleaner
    when=`jul2ymd "$y" "$d"`
    # Not leap year check: skip date that doesn't fall in current year $y
    if [ ${when:0:4} -eq "$y" ]
    then
        # I'm wary of octal interpretation, even if ireelevant w/ our FH's
        for cycle in $CYCLE
        do
            process_day_cycle $when $cycle  2>>"$LOG_FILE"
        done

        if [[ $MUR_CROP ]]
        then
            # Crop MUR SST file for given day as well
            crop_mur $when 2>>"$LOG_FILE"
        fi

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
