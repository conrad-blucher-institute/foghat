#!/usr/bin/env sh

process() {
    local date=$1
    local cycle=$2
    echo "?Processing $date, model cycle $cycle, looking for NaNs"
    ./maps_input.sh -p -c $cycle $date $date
    local t=`echo /tmp/tmp.*maps_input`
    cd $t
    echo "?Searching input grib2 files for any NaNs:"
    for i in *_raw.grb2
    do
        echo "    $i"
        wgrib2 -stats $i | ack -v 'undef=0:'
    done
    cd - >/dev/null
    rm -r $t
}

# DQDZ1000SFC
process 2019-04-08 6
process 2019-04-11 0
process 2019-04-23 12
process 2019-07-12 0
process 2019-07-12 18
process 2019-10-13 18

# DQDZ700725
process 2019-01-28 18
process 2019-01-30 0
