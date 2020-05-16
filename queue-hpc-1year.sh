#!/usr/bin/env bash

# Automate scheduling one year of data processing
# Split the processing across four jobs, one for each model cycle (0, 6, 12, 18)

# XXX Assumes your _customized_ HPC sbatch script is in hpc_maps.sbatch

function getjobid() {
    # sbatch outputs job ID message to stderr
    local jobid=`$* 2>&1 | grep -Pi -o 'job \d+\b' | sed -r 's/^job //gi;'`
    echo "$jobid"
}

# Simple sanity check on input
year=$1
if [[ $year -lt 2009 || $year -gt 2030 ]]
then
    echo "?Usage: $0 <year>"
    exit
fi

echo "?Queueing data processing jobs for data year $year"
j1=$(getjobid sbatch --job-name "fogm${year:2}00" hpc_maps.sbatch -c 0  $year-01-01 $year-12-31)
j2=$(getjobid sbatch --job-name "fogm${year:2}06" hpc_maps.sbatch -c 6  $year-01-01 $year-12-31)
j3=$(getjobid sbatch --job-name "fogm${year:2}12" hpc_maps.sbatch -c 12 $year-01-01 $year-12-31)
j4=$(getjobid sbatch --job-name "fogm${year:2}18" hpc_maps.sbatch -c 18 $year-01-01 $year-12-31)

echo "?Data processing job IDs: $j1, $j2, $j3, $j4"
RULE=afterok:$j1:$j2:$j3:$j4

# Have slurm wait to run the following job until the previous 4 jobs complete (successfully)
echo "?Queueing tarball job once processing jobs complete ($RULE)"
sbatch --job-name "fogtar${year:2}" --dependency="$RULE" hpc_tarball.sbatch $year
