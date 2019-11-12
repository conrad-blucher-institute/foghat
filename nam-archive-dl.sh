#!/usr/bin/env bash

# Download archival NAM data from a NOAA AIRS order

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

usage () {
    local zero=`basename $0`
    echo "$zero <email_id> <order_id> <url>"
    exit
}

if [[ -z "$1" || -z "$2" || -z "$3" ]]
then
    usage
fi
EMAIL_ID=$1
ORDER_ID=$2
URL=$3

ARCHIVE_DIR=$FOGHAT_ARCHIVE_DIR/nam-grib
TMP_DIR=$FOGHAT_BASE/tmp
VAR_DIR=$FOGHAT_BASE/var
DOWNLOAD_TARGET=$TMP_DIR/$ORDER_ID
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/order_$ORDER_ID-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR $ARCHIVE_DIR $TMP_DIR $VAR_DIR

NOW=`date`
echo "# $EMAIL_ID, $ORDER_ID, $URL" >>$LOG_FILE
echo "Downloading files from $URL at $NOW" >>$LOG_FILE

# See https://www.ncdc.noaa.gov/has/has.orderguide for suggestions
# I'd try to reject 'index.html?C=*' variants but wget on gridftp (v1.12) is too old to support --reject-regex :(
WGET_START=`date -u '+%s'`
/usr/bin/wget -erobots=off --reject 'robots.txt' -nv --no-parent -r --timestamping --append-output=$LOG_FILE -nd --directory-prefix=$DOWNLOAD_TARGET  $URL
WGET_END=`date -u '+%s'`
DELTA=$((WGET_END - WGET_START))
echo "?downloaded files in $URL in $DELTA seconds" >>$LOG_FILE

# Cleanup temporary download directory
pushd $PWD >/dev/null
cd $DOWNLOAD_TARGET
# Remove index.html?C=*
rm 'index.html?'*

# Strip file list from index.html  [assuming it was downloaded] and archive both files
TXT_FN=file_list_${ORDER_ID}.txt
HTML_FN=index_${ORDER_ID}.html
grep -oiP '(?<=href=")(nam[^"]+tar)(?=")' index.html >file_list_${ORDER_ID}.txt
mv index.html $HTML_FN

# Stop processing if we're missing any files so we can efficiently re-run job
missing=0
for i in `cat $TXT_FN`
do
    if [ ! -e "$i" ]
    then
        missing=$((missing + 1))
    fi
done
if [ $missing -gt 0 ]
then
    echo -e "?$missing file(s) missing from $DOWNLOAD_TARGET directory.  Exiting early so job can be restarted/requeued.\n" >>$LOG_FILE
    ZERO=`basename $0`
    echo "To restart job, run:\n    $ZERO $*\n" >>$LOG_FILE
    exit 1
else
    echo "?All expected files present in $DOWNLOAD_TARGET" >>$LOG_FILE
fi

# Kluge!  Figure out destination directories in case we need to create them
DEST_PATHS=`perl -e '%paths; while (<>) { chomp; ($t,$yr) = ( m/^nam(anl|)_218_(\d{4})\d{6}.g2.tar$/ ); $t ||= "nmm"; $paths{"$t/$yr"}++; } print join("\n",keys %paths)."\n"; ' $TXT_FN`
for i in $DEST_PATHS
do
    p=$ARCHIVE_DIR/$i
    echo "Ensuring archive directory $p exists" >>$LOG_FILE
    mkdir -p $p
done

# Copy/archive filelist w/ order ID somewhere.  E.g., file_list_$ORDER_ID.txt
mv $TXT_FN $HTML_FN $VAR_DIR

# Move files to correct archive directory (somewhere under $ARCHIVE_DIR)
echo "Moving files to archive directory:" >>$LOG_FILE
# Put nam_218_2009052200.g2.tar [NAM-NMM] files in $ARCHIVE_DIR/nmm/$year
for i in nam_218_*.g2.tar
do
    # If matching filenames _don't_ exist in this path, skip it
    if [ ! -e $i ]
    then
        break
    fi
    year=`echo $i | sed -r 's/(^nam_218_|[0-9]{6}.g2.tar$)//g;'`
    mv $i $ARCHIVE_DIR/nmm/$year/
    echo "  • $i → $ARCHIVE_DIR/nmm/$year/$i" >>$LOG_FILE
done
# Put namanl_218_2009052100.g2.tar [NAM-ANL] files in  $ARCHIVE_DIR/anl/$year
for i in namanl_218_*.g2.tar
do
    if [ ! -e $i ]
    then
        break
    fi
    year=`echo $i | sed -r 's/(^namanl_218_|[0-9]{6}.g2.tar$)//g;'`
    mv $i $ARCHIVE_DIR/anl/$year/
    echo "  • $i → $ARCHIVE_DIR/anl/$year/$i" >>$LOG_FILE
done

popd >/dev/null

# TODO  Unpack files?!  I'm thinking not yet or at least not w/o per-day directories :\

# Final cleanup
rmdir $DOWNLOAD_TARGET

# Move AIRS order email to "processed" folder (i.e., state change)
./ncei_email.py move $ORDER_ID Queued Processed >>$LOG_FILE 2>&1
