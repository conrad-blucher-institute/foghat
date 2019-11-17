#!/usr/bin/env bash

# Check state of requests for archive NAM (NOAA's AIRS)

if [[ -z "$FOGHAT_BASE" || -z "$FOGHAT_LOG_DIR" || -z "$FOGHAT_ARCHIVE_DIR" || -z "$FOGHAT_EMAIL" ]]
then
    echo "?FOGHAT Environment variables not defined, see etc/sample-environment.sh" 1>&2
    exit
fi

TODAY=`date -u '+%Y%m%d'`

# TODO  Don't need this at the moment
REQUEST_DIR=$FOGHAT_BASE/var/requests

if [ ! -x /usr/bin/jq ]
then
    echo "?You need to install JQ <https://stedolan.github.io/jq/> to run this script"
    exit
fi

LIMIT=69                                # 👈 😎 👈
JSON_FILE=`mktemp --suffix=-${TODAY}-orders.json`

/usr/bin/curl -# "https://www.ncdc.noaa.gov/airs/GetOrders?email=$FOGHAT_EMAIL&limit=$LIMIT&offset=1" \
-H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:70.0) Gecko/20100101 Firefox/70.0' \
-H 'Accept: */*' \
-H 'Accept-Language: en-US,en;q=0.5' \
--compressed -H 'X-Requested-With: XMLHttpRequest' \
-H 'DNT: 1' -H 'Connection: keep-alive' \
-H "Referer: https://www.ncdc.noaa.gov/cdo-web/orders?email=$FOGHAT_EMAIL" \
--output $JSON_FILE

TOTAL=`jq '.metadata.count' $JSON_FILE`
echo "For the last $LIMIT (out of $TOTAL) requests submitted to AIRS by $FOGHAT_EMAIL:"
# XXX  I'm sure my jq command can be improved, but just wanted to get something generally useful out of this
jq  -c '[.orders[] | {id:.id ,status:.status}] | group_by(.status) | .[] | [.[].status] | [(unique|.[]),length] '  $JSON_FILE

