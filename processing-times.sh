#!/usr/bin/env bash

# Display histogram of processing times for HPC analysis/troubleshooting

function histo()
{
    local file=$1
    local binsize=$2

    # Calculate consistent ranges for gsl-histogram that cover all possible values
    min=`sort -n $file | head -1`
    max=`sort -n $file | tail -1`
    lower=$((min - (min % binsize)))
    upper=$((max + (binsize - (max % binsize) )))
    bins=$(((upper - lower) / binsize))
    echo "Saw min=$min, max=$max, want binsize=$binsize → lower=$lower, upper=$upper, bins=$bins"

    cat $file | gsl-histogram $lower $upper $bins
}

function stats()
{
    local file=$1
    # Adapted from https://stackoverflow.com/a/15101429/1502174
    awk '{sum+=$1; sumsq+=$1*$1} END { mean=sum/NR; stddev=sqrt(sumsq/NR - (sum/NR)**2); print "mean "mean," stddev "stddev; }' $file
}

# Defaults
BINSIZE=20

# Parse command line options
while getopts "b:" OPTION; do
    case $OPTION in
    b)
        BINSIZE=$OPTARG
        ;;
    *)
        echo "Incorrect option ($OPTION) provided"
        exit 1
        ;;
    esac
done
# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
shift $((OPTIND -1))

TMPFILE=`mktemp`
HALF=`mktemp`
files=$*
echo "# Processing log file(s) $files"
# Total number of (days, model cycles) processed
grep -hPo '\d+ seconds$' $files | sed 's/ seconds$//;' >$TMPFILE
n=`wc -l $TMPFILE | grep -oP '^\d+'`

echo "## Model-cycle processing times ($n total)"
histo $TMPFILE $BINSIZE
echo ""
stats $TMPFILE
echo ""

mid=$((n / 2))

head --lines=$mid $TMPFILE >$HALF
echo "## 1H Model-cycle processing times [1, $mid]"
histo $HALF $BINSIZE
echo ""
stats $HALF
echo ""

mid=$((mid + 1))                        # avoid overlap
tail --lines="+$mid" $TMPFILE >$HALF
echo "## 2H Model-cycle processing times [$mid, $n]"
histo $HALF $BINSIZE
stats $HALF
echo -e "\n-- 8< --\n"

rm $TMPFILE $TMPFILE2
