#!/usr/bin/env bash

# Normalize archived visibility probability data from Matthew Pyle to
# match folder structure and filenames as saved by the HREF download
# script

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_EXE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

MPYLE_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/mpyle-href-vis
HREF_ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-href
# Uncomment following variable if debugging
#LIMIT=5

# Add date to/modify filename as per Waylon and be consistent w/ href-download.sh
rename_w_date() {
    local date=$1
    local fqpn="$HREF_ARCHIVE_DIR/$date"

    if [ ! -d "$fqpn" ]
    then
        echo "?Looks like there aren't any files for $date yet, skipping" 1>&2
        return
    fi

    cd $fqpn
    echo "?Adding dates to filenames in $fqpn" 1>&2
    for i in *
    do
        # E.g. href.t00z.conus.prob.f12.grib2_vis → href.t00z.conus.prob.f12.20171201.grib2
        j=`echo $i | sed "s/\.\(f[0-3][0-9]\)\.grib2_vis$/.\1.${date}.grib2/;"`
        if [ ! -e $j ]
        then
            mv $i $j
        fi
    done
    cd - >/dev/null
}

# For each of the date range directories in mpyle-href-vis, e.g. 20171201-20180131
#     and each HREF tar file w/in that directory, e.g. href.20171224.tar
count=1
for tarfile in $MPYLE_ARCHIVE_DIR/*/href.*.tar
do
    base=`basename $tarfile`
    echo "[$count] Unpacking $base archive to $HREF_ARCHIVE_DIR" 1>&2
    tar xf $tarfile --directory $HREF_ARCHIVE_DIR
    dirname=${base%%.tar}
    # Rename folder.  E.g. href.20171201 → 20171201
    onlydate=${dirname##href.}
    from_dir="$HREF_ARCHIVE_DIR/$dirname"
    to_dir="$HREF_ARCHIVE_DIR/$onlydate"
    if [[ -d "$to_dir" ]]
    then
        echo "?Destination folder ($to_dir) already exists.  Will *NOT* replace with $from_dir.  Skipping"
    else
        mv "$HREF_ARCHIVE_DIR/$dirname" "$to_dir"
        # Rename files within new subdirectory (e.g. 20171201) to include date.
        rename_w_date $onlydate
    fi
    # Early exit (probably just debugging)
    [[ $LIMIT && $count -ge $LIMIT ]] && break
    count=$((count + 1))
done

echo "?Unpacked $count tar files w/ archived HREF probabilistic visibility data"
