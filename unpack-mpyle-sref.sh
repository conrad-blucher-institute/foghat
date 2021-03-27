#!/usr/bin/env bash

# Normalize archived visibility probability data from Matthew Pyle to
# match folder structure and filenames as saved by the SREF download
# script

# XXX  There are some differences between the archived SREF data tarballs Matthew provided compared to the HREF tarballs.  KISS meant copying the HREF script and modifying it of something fancier

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_EXE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

MPYLE_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/mpyle-sref-vis
SREF_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-sref
# Uncomment following variable if debugging
#LIMIT=5

# Add date to/modify filename as per Waylon and be consistent w/ sref-download.sh
rename_w_date() {
    local date=$1
    local year=${date:0:4}
    local fqpn="$SREF_ARCHIVE_DIR/$year/$date"

    if [ ! -d "$fqpn" ]
    then
        echo "?Looks like there aren't any files for $date yet, skipping" 1>&2
        return
    fi

    cd $fqpn
    echo "?Adding dates to filenames in $fqpn" 1>&2
    for i in ensprod/*
    do
        # E.g. ensprod/sref.t03z.pgrb132.prob_3hrly.grib2_combo → sref.t03z.pgrb132.prob_3hrly.20190801.grib2
        j=`echo $i | sed "s/\.prob_3hrly\.grib2_combo$/.prob_3hrly.${date}.grib2/;  s/^ensprod\///;" `
        if [ ! -e $j ]
        then
            mv $i $j
        fi
    done
    rmdir ensprod
    cd - >/dev/null
}

# For each of the date range directories in mpyle-sref-vis, e.g. 20171201-20180131
#     and each SREF tar file w/in that directory, e.g. sref.20171224.tar
count=1
for tarfile in $MPYLE_ARCHIVE_DIR/*/sref_*.tar
do
    base=`basename $tarfile`
    echo "[$count] Unpacking $base archive to $SREF_ARCHIVE_DIR" 1>&2
    tar xf $tarfile --directory $SREF_ARCHIVE_DIR
    dirname=`echo ${base%%.tar} | sed 's/_/./;'`
    # Rename folder.  E.g. sref_20171201 → 20171201
    onlydate=${dirname##sref.}
    year=${onlydate:0:4}
    from_dir="$SREF_ARCHIVE_DIR/$dirname"
    to_dir="$SREF_ARCHIVE_DIR/$year/$onlydate"
    [[ ! -d "$SREF_ARCHIVE_DIR/$year" ]] && mkdir -p "$SREF_ARCHIVE_DIR/$year"
    if [[ -d "$to_dir" ]]
    then
        echo "?Destination folder ($to_dir) already exists.  Will *NOT* replace with $from_dir.  Skipping" 1>&2
    else
        mv "$SREF_ARCHIVE_DIR/$dirname" "$to_dir"
        # Rename files within new subdirectory (e.g. 20171201) to include date.
        rename_w_date $onlydate
    fi
    # Early exit (probably just debugging)
    [[ $LIMIT && $count -ge $LIMIT ]] && break
    count=$((count + 1))
done

echo "?Unpacked $count tar files w/ archived SREF probabilistic visibility data"
