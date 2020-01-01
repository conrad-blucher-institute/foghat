#!/usr/bin/env bash

# Generate Deep Learning Neural Net MapS fog input data for Hamid

# Bounding box for Hamid's MapS DL NN
LON_LAT='-97.7:-96 27:28.5'

# MUR SST ncks latitude/longitude filtering CLI options (should match above)
MUR_NCKS_ARGS='-d lat,27.0,28.5 -d lon,-97.7,-96.0'

# Build a single regex w/ all the predictors at all the levels we want
ATMOSPHERIC=':(TMP|RH|UGRD|VGRD|TKE|VVEL):(700|725|750|775|800|825|850|875|900|925|950|975|1000) mb:'
ABOVE_GROUND=':(TMP|DPT|RH|UGRD|VGRD):(2|10) m above ground:'
# Surface pressure is only used to calculate derived parameter(s)
SURFACE=':(FRICV|VIS|PRES):surface:'
MATCH_RE="($ATMOSPHERIC|$ABOVE_GROUND|$SURFACE)"

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

# TODO  Create notes file to contain missing days/data for NetCDF data consumers

mkdir -p "$FOGHAT_LOG_DIR"  "$OUTPUT_DIR"

# Ensure (process-specific) local node storage for all temporary files
TMP_DIR=`mktemp -d --suffix=.${TODAY}-maps_input`


process_grib_file() {
    local filename=$1
    local noext=`echo $filename | sed 's/^nam_218/maps/; s/\.grb2//;'`
    local unsorted=${noext}_raw.grb2
    local sorted=${noext}_sorted.grb2
    local netcdf=${noext}_wip.nc
    local final_netcdf=${noext}_input.nc

    # Clip out the variables and levels we want w/in the desired bounding box
    wgrib2 $filename -set_grib_type c2 -match "$MATCH_RE" -small_grib $LON_LAT $unsorted >/dev/null

    # Reorder grib2 variables [predictors] as noted in Waylon's document
    wgrib2 $unsorted | $FOGHAT_EXE_DIR/grib2_inv_reorder.pl | wgrib2 -i $unsorted -set_grib_type c2 -grib_out $sorted >/dev/null

    # Convert to NetCDF
    wgrib2 $sorted -netcdf $netcdf >/dev/null

    # Using variables in NetCDF file, add derived variables (in place)
    $FOGHAT_EXE_DIR/maps_derived.py $netcdf

    # Remove pressure at surface (PRES_surface) from NetCDF file, as per Waylon
    ncks --no_alphabetize -O -x -v PRES_surface $netcdf $final_netcdf
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
        # TODO  Log error somewhere else (notes)
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
    echo "?$count forecast hour files processed from $fn in $delta_t seconds" 1>&2

    # Count should be 37 files, if not then log [somewhere else], [probably] discard?
    if [ $count -ne $EXPECTED_COUNT ]
    then
        # TODO  Add message/note about missing day/model cycle
        echo "?Only saw $count .grb2 files after processing ($year$md, $cycle) grib tarfile, expected $EXPECTED_COUNT.  Skipping model cycle" 1>&2
        # Remove files from temporary directory so we don't fill up disk on errors
        rm *.nc *.grb2
        return
    fi

    # Copy resulting MapS input files to destination directory for given day
    local output_subdir=`date -d "$when" '+%Y/%Y%j'`
    local dest_path="$OUTPUT_DIR/$output_subdir"
    mkdir -p "$dest_path"
    cp maps_$year*_input.nc "$dest_path"

    # TODO  [optional] CLI option to copy temporary (WIP) NetCDF files ± source [clipped/sorted] .grb2 files into destination directory for verification

    # Remove files _from_ temporary directory (but not directory itself) before next call
    rm *.nc *.grb2
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
    local dest_fqpn="$dest_path/mur_${murdate}090000_crop.nc"

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
echo "?generating MapS input data from $1 ($year1,$doy1) to $2 ($year2,$doy2) on $now" >>"$LOG_FILE"

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
        for cycle in 0 6 12 18
        do
            process_day_cycle $when $cycle  2>>"$LOG_FILE"
        done
        # Crop MUR SST file for given day as well
        crop_mur $when 2>>"$LOG_FILE"
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
echo "?processed $count day(s) of data in $elapsed time" >>"$LOG_FILE"

# Remove temporary directory (but should already be empty)
echo "?removing temporary directory, $TMP_DIR" >>"$LOG_FILE"
rm -r $TMP_DIR
