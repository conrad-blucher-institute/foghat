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


TMPFILE=`mktemp`
HALF=`mktemp`
for i in $*
do
    echo "# Processing log file $i"
    # Total number of (days, model cycles) processed
    grep -Po '\d+ seconds$' $i | sed 's/ seconds$//;' >$TMPFILE
    n=`wc -l $TMPFILE | grep -oP '^\d+'`

    echo "## Model-cycle processing times ($n total)"
    histo $TMPFILE 20
    echo ""
    stats $TMPFILE
    echo ""

    mid=$((n / 2))

    head --lines=$mid $TMPFILE >$HALF
    echo "## 1H Model-cycle processing times [0, $mid]"
    histo $HALF 20
    echo ""
    stats $HALF
    echo ""

    tail --lines="+$mid" $TMPFILE >$HALF
    echo "## 2H Model-cycle processing times [$mid, $n]"
    histo $HALF 20
    stats $HALF
    echo -e "\n-- 8< --\n"
done

rm $TMPFILE $TMPFILE2
