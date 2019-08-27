#!/usr/bin/env bash

# Rsync folder from master archive (gridftp, b/c it has the most space) to archive on this machine

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

if [[ -z "$1" ]]
then
    echo "?Need to specify what archive subfolder to rsync" 1>&2
    exit
fi
subdir=$1

TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/rsync-$subdir-$TODAY.log"

cd $FOGHAT_ARCHIVE_DIR
cd $subdir
# Assumes you have public key SSH setup and key loaded
rsync -aHvzhe ssh --log-file=$LOG_FILE gridftp:/work/TANN/fog-data/archive/$subdir/ .

