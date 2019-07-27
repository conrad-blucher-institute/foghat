#!/usr/bin/env bash

# Download href visibility archive data from Matthew Pyle's temporary store he setup for Waylon
#
# Looks like he posts two months of data (~8GB) at a time.  Waylon
# emails me whenever a new data set is made available

URL='ftp://ftp.emc.ncep.noaa.gov/mmb/WRFtesting/mpyle/vis_tmp/'

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/mpyle-href-vis/latest
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/vis_archive-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR $ARCHIVE_DIR

/usr/bin/wget -nv --no-parent -r --limit-rate=5m --wait=5 --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$ARCHIVE_DIR  $URL

# Calculate md5sums of all archive files and rename directory as date range
pushd $PWD
cd $ARCHIVE_DIR
first=`ls -1 href.* | cut -c 6-13 | head -1`
last=` ls -1 href.* | cut -c 6-13 | tail -1`
/usr/bin/md5sum href.*.tar > href-$first-$last.md5
cd ..
mv $ARCHIVE_DIR "$first-$last"
popd

