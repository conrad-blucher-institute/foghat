#!/usr/bin/env bash

# Remove non-dated conus.prob filenames from archive directories (avoid needless duplication)

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

cleanup_href_directory() {
    local date=$1
    local year=${date:0:4}

    # How many hard linked filenames should we expect to see in a given day's nomad's href [conus.prob] archive directory?
    local dated_files_count=144

    # Because of the suffed way I'm handling directory discovery, this date may not have any HREF data
    local dest_path="nomads-href/$year/$date"
    [[ ! -d "$dest_path" ]] && return

    # Before we change _anything_, make sure we see what we expect
    pushd $PWD >/dev/null
    cd $dest_path
    local count=`ls -1 href.t[01][0268]z.conus.prob.f[0123][0-9].$date.grib2 | wc -l`
    if [[ $count != $dated_files_count ]]
    then
        echo "?Found $count dated files (...$date.grib2), but expected $dated_files_count.  Skipping directory $date "
        popd >/dev/null
        return
    fi

    # Remove un-dated version of filenames (_should_ be a hard link)
    find ./ -name 'href.t[01][0268]z.conus.prob.f[0123][0-9].grib2' | xargs -r -n1 unlink
    popd >/dev/null
}

cleanup_sref_directory() {
    local date=$1
    local year=${date:0:4}

    # How many hard linked filenames should we expect to see in one day's NOMADS SREF archive directory?
    local dated_files_count=8

    # Because of the way I'm handling directory discovery, this date may not have any HREF data :(
    local dest_path="nomads-sref/$year/$date"
    [[ ! -d "$dest_path" ]] && return

    # Before we change _anything_, make sure we see what we expect
    pushd $PWD >/dev/null
    echo cd "$dest_path"
    cd "$dest_path"
    local count=`ls -1 sref.t{03,09,15,21}z.pgrb132.prob_3hrly.$date.grib2{,.idx} | wc -l`
    if [[ $count != $dated_files_count ]]
    then
        echo "?Found $count dated files (...${date}.grib2), but expected $dated_files_count.  Skipping directory $date "
        popd >/dev/null
        return
    fi

    # Remove un-dated version of filenames (_should_ be a hard link)
    # XXX  find [file]names don't appear to support {03,09,...} globbing → [] character class syntax
    find ./ -name "sref.t[012][3951]z.pgrb132.prob_3hrly.grib2" -or -name "sref.t[012][3951]z.pgrb132.prob_3hrly.grib2.idx" | xargs -r -n1 unlink

    popd >/dev/null
}

# How far back to go for cleanup
start_date=$1
[[ -z "$start_date" ]] && start_date='30 days ago'

# What range of archive date directories should we process?
first=`date -d "$start_date" '+%Y%m%d'`
last=`date -d '7 days ago' '+%Y%m%d'`

if [[ -z "$first" ]]
then
    echo "?No starting date \"$first\".  Was the provided start date (\"$start_date\") valid? ?" 2>&1
    exit 1
fi

echo "Cleaning up HREF and SREF archive directories between $first and $last dates."
pushd $PWD >/dev/null
cd $FOGHAT_ARCHIVE_DIR
for i in nomads-[sh]ref/*/*
do
    # This _is_ kluge but I've spent too much time on SREF data d/l already :(
    j=`basename $i`                     # just the date (YYYYMMDD)
    if [[ $j > $first && $j < $last ]]
    then
        echo "?processing directory $i"
        cleanup_href_directory $j
        cleanup_sref_directory $j
    fi
done
popd >/dev/null
