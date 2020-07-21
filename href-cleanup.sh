#!/usr/bin/env bash

# Remove non-dated conus.prob filenames from archive directories (avoid needless duplication)

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nomads-href

# How many hard linked filenames should we expect to see in a given day's nomad's href [conus.prob] archive directory?
DATED_FILES_COUNT=144

cleanup_href_directory() {
    local date=$1

    # Before we change _anything_, make sure we see what we expect
    pushd $PWD >/dev/null
    cd $date
    local count=`ls -1 href.t[01][0268]z.conus.prob.f[0123][0-9].$date.grib2 | wc -l`
    if [ $count != $DATED_FILES_COUNT ]
    then
        echo "?Found $count dated files (...$date.grib2), but expected $DATED_FILES_COUNT.  Skipping directory $date "
        popd >/dev/null
        return
    fi

    # Remove un-dated version of filenames (_should_ be a hard link)
    find ./ -name 'href.t[01][0268]z.conus.prob.f[0123][0-9].grib2' | xargs -r -n1 unlink
    popd >/dev/null
}

# How far back to go for cleanup
start_date=$1
[ -z "$start_date" ] && start_date='30 days ago'

# What range of archive date directories should we process?
first=`date -d "$start_date" '+%Y%m%d'`
last=`date -d '3 days ago' '+%Y%m%d'`

if [ -z "$first" ]
then
    echo "?No starting date \"$first\".  Was the provided start date (\"$start_date\") valid? ?" 2>&1
    exit 1
fi

echo "Cleaning up HREF directories between $first and $last."
pushd $PWD >/dev/null
cd $ARCHIVE_DIR
for i in *
do
    if [[ $i > $first && $i < $last ]]
    then
        echo "?processing directory $i"
        cleanup_href_directory $i
    fi
done
popd >/dev/null
