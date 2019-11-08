#!/usr/bin/env bash

# Submit requests for archive NAM data to NOAA's AIRS web interface

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_EMAIL" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

REQUEST_DIR=$FOGHAT_BASE/var/requests

TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$FOGHAT_LOG_DIR/request_nam_data-$TODAY.log"

mkdir -p $FOGHAT_LOG_DIR  $REQUEST_DIR

# Wait a few seconds
random_sleep() {
    local seconds=$((RANDOM % 8 + 1))
    echo "?sleeping $seconds seconds" >>$LOG_FILE
    sleep $seconds
}

request_data() {
    local dataset=$1                    # NAMANL218 or NAM218
    local cycle=$2                      # either 00, 06, 12, 18
    local date0=$3                      # from date
    local date1=$4                      # to date

    read begyear begmonth begday <<<`date -d $date0 '+%Y %m %d' `
    read endyear endmonth endday <<<`date -d $date1 '+%Y %m %d' `
    output="$REQUEST_DIR/archive-request-$dataset-$cycle-$begyear$begmonth$begday-$endyear$endmonth$endday.html"

    # Random sleep between requests so we don't look _that_ obvious
    random_sleep

    echo "?requesting dataset $dataset, cycle $cycle from $begyear-$begmonth-$begday to $endyear-$endmonth-$endday" >>$LOG_FILE
    curl -# 'https://www.ncdc.noaa.gov/has/HAS.FileSelect'  \
-H 'User-Agent: Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:70.0) Gecko/20100101 Firefox/70.0'  \
-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'  \
-H 'Accept-Language: en-US,en;q=0.5'  \
--compressed  \
-H 'Content-Type: application/x-www-form-urlencoded'  \
-H 'Origin: https://www.ncdc.noaa.gov'  \
-H 'Connection: keep-alive'  \
-H "Referer: https://www.ncdc.noaa.gov/has/HAS.FileAppRouter?datasetname=$dataset&subqueryby=STATION&applname=&outdest=FILE"  \
-H 'Cookie: has_js=1'  \
-H 'Upgrade-Insecure-Requests: 1'  \
-H 'DNT: 1'  \
--data "satdisptype=N%2FA&stations=$cycle&station_lst=&typeofdata=MODEL&dtypelist=&begdatestring=&enddatestring=&begyear=$begyear&begmonth=$begmonth&begday=$begday&beghour=&begmin=&endyear=$endyear&endmonth=$endmonth&endday=$endday&endhour=&endmin=&outmed=FTP&outpath=&pri=500&datasetname=$dataset&directsub=Y&emailadd=$FOGHAT_EMAIL&outdest=FILE&applname=&subqueryby=STATION&tmeth=Awaiting-Data-Transfer" \
--output $output >>$LOG_FILE
}

# Print usage and die
usage () {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage: $zero <year>

E.g., $zero 2010

Request archived NAM-NMM and NAM-ANL data for the entire specified year, for all model cycle times (00, 06, 12, 18)
EndOfUsage
    exit
}

[[ -z "$1" ]] && usage

YEAR=$1
if ((YEAR < 2000 || YEAR > 2021))
then
    echo "Invalid year $YEAR"
    usage
fi

NOW=`date`
echo "?starting request set for NAM data covering year $YEAR on $NOW" >>$LOG_FILE

# One year of NAM-NMM data gets too big for a single request (max size
# 250GB), so we have to break up a single year into separate requests.  At
# it's largest data size (in 2019), we can only request a maxmium of ~83
# days and still be under 250GB, hence breaking up the year into ~2.5 month
# periods

# TODO  Dry run mode or confirmation prompt just in case the wrong year is specified

for cycle in '00' '06' 12 18
do
    request_data NAM218 $cycle "$YEAR-01-01" "$YEAR-03-15"
    request_data NAM218 $cycle "$YEAR-03-16" "$YEAR-05-31"
    request_data NAM218 $cycle "$YEAR-06-01" "$YEAR-08-15"
    request_data NAM218 $cycle "$YEAR-08-16" "$YEAR-10-31"
    request_data NAM218 $cycle "$YEAR-11-01" "$YEAR-12-31"

    # NAM-ANL is small enough to request a full year at a time
    request_data NAMANL218 $cycle "$YEAR-01-01" "$YEAR-12-31"
done

