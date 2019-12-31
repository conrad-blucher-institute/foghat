#!/usr/bin/env bash

# Generate Deep Learning Neural Net MapS fog input data for Hamid

# Bounding box for Hamid's MapS DL NN
LAT_LON='-97.7:-96 27:28.5'

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

# NAM directory layout needs to match values in any other files
NMM_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nam-grib/nmm

OUTPUT_DIR=$FOGHAT_INPUT_DIR/input/fog-maps
TODAY=`date -u '+%Y%m%d'`
# Include PID in log filename in case multiple instances of this process are running simultaneously
LOG_FILE="$FOGHAT_LOG_DIR/maps_input-$TODAY-$$.log"

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
    wgrib2 $filename -set_grib_type c2 -match "$MATCH_RE" -small_grib $LAT_LON $unsorted >/dev/null 2>>"$LOG_FILE"

    # Reorder grib2 variables [predictors] as noted in Waylon's document
    wgrib2 $unsorted | $FOGHAT_EXE_DIR/grib2_inv_reorder.pl | wgrib2 -i $unsorted -set_grib_type c2 -grib_out $sorted >/dev/null 2>>"$LOG_FILE"

    # Convert to NetCDF
    wgrib2 $sorted -netcdf $netcdf >/dev/null 2>>"$LOG_FILE"

    # Using variables in NetCDF file, add derived variables (in place)
    $FOGHAT_EXE_DIR/maps_derived.py $netcdf 2>>"$LOG_FILE"

    # Remove pressure at surface (PRES_surface) from NetCDF file, as per Waylon
    ncks --no_alphabetize -O -x -v PRES_surface $netcdf $final_netcdf
}

# Process all forecast hours files in a given (date, model cycle) tarfile
process_day_cycle() {
    local day=$1
    local cycle=$2

    local start_t=`date '+%s'`

    local ymd=`date -d "$day" '+%Y %m%d'`
    read year md <<<$ymd                # year, month+day
    printf -v mc '%02d' $cycle          # model cycle, formatted

    # For given date, cycle, build .tar filename
    local tarfile=$NMM_ARCHIVE_DIR/$year/nam_218_$year$md$mc.g2.tar
    echo "?Extracting forecast hour files from $tarfile ($year$md, $cycle)" >>"$LOG_FILE"

    if [[ ! -e $tarfile ]]
    then
        # TODO  Log error somewhere else
        echo "?Can't find ($year$md, $cycle) grib tarfile, $tarfile " >>"$LOG_FILE"
        return
    fi

    # Extract forecast hours 0-36 from (day, model cycle) grib tarfile
    # XXX  CLI testing made it seem I have to be _really_ specific w/ my file glob otherwise it matches unwanted files?!
    local grib_files=`tar xvf "$tarfile" --directory=$TMP_DIR --wildcards nam_218_$year${md}_${mc}00_0{[012][0-9],3[0-6]}.grb2`

    pushd $PWD >/dev/null
    cd $TMP_DIR

    # Process NAM grib files
    local count=0
    for fn in $grib_files
    do
        # Check for errors/unavailable files ?
        process_grib_file $fn
        count=$((count + 1))
    done
    popd >/dev/null

    local delta_t=$((`date '+%s'` - start_t))
    echo "?$count forecast hour files processed from $fn in $delta_t seconds" >>"$LOG_FILE"

    # TODO count should be 37 files, if not then log [somewhere else], possibly discard?
}


process_day_cycle  2018-06-24 00

# TODO  Process MUR SST file for given day as well (cKip)

# TODO  Compare/dump grb2 file with pure converted NetCDF file to ensure contents are the same

# Clean up /tmp directory so it doesn't fill up
echo "?cleaning up temporary directory, $TMP_DIR" >>"$LOG_FILE"
#rm -r $TMP_DIR
