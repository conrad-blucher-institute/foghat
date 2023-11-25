#!/usr/bin/env bash

# Download href/sref visibility archive data from Matthew Pyle's temporary store he setup for Waylon
#
# Looks like he posts two months of data (~8GB) at a time.  Waylon
# emails me whenever a new data set is made available

PREFIX=${1:-sref}

URL='ftp://ftp.emc.ncep.noaa.gov/mmb/WRFtesting/mpyle/vis_tmp/'

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/mpyle-$PREFIX-vis/latest
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/mpyle_archive-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR $ARCHIVE_DIR

/usr/bin/wget -nv --no-parent -r $FOGHAT_WGET_OPTIONS --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$ARCHIVE_DIR  $URL

# Calculate md5sums of all archive files and rename directory as date range
echo "?Calculating MD5 sums of archive files" >>$LOG_FILE
pushd $PWD
cd $ARCHIVE_DIR
FIRST=`ls -1 $PREFIX?* | cut -c 6-13 | head -1`
LAST=` ls -1 $PREFIX?* | cut -c 6-13 | tail -1`
DATE_RANGE="$FIRST-$LAST"
MD5_FILE="$PREFIX-$DATE_RANGE-md5.txt"
/usr/bin/md5sum $PREFIX?*.tar > $MD5_FILE
cd ..
echo "?Renaming $ARCHIVE_DIR as $DATE_RANGE" >>$LOG_FILE
mv $ARCHIVE_DIR "$DATE_RANGE"

# Send email w/ download/checksum information
echo "?Sending notification email to $FOGHAT_NOTIFY_EMAIL" >>$LOG_FILE
mailx -s "$PREFIX download on $HOSTNAME" -a "$DATE_RANGE/$MD5_FILE"  $FOGHAT_NOTIFY_EMAIL <<EOL
Attention meatbag,

Download on $HOSTNAME, started on $TODAY, for $PREFIX data between $DATE_RANGE has finished.  MD5 checksum file attached.

Logfile is located at $LOG_FILE

HAND


EOL

# Go home
popd
