#!/usr/bin/env bash

# Automate scheduling one year of data processing
# Split the processing across four jobs, one for each model cycle (0, 6, 12, 18)

# XXX Assumes your _customized_ HPC sbatch script is in hpc_maps.sbatch

# Simple sanity check on input
year=$1
if [[ $year -lt 2009 || $year -gt 2030 ]]
then
    echo "?Usage: $0 <year>"
fi

echo "?Queueing jobs for data year $year"
sbatch hpc_maps.sbatch -c 0  $year-01-01 $year-12-31
sbatch hpc_maps.sbatch -c 6  $year-01-01 $year-12-31
sbatch hpc_maps.sbatch -c 12 $year-01-01 $year-12-31
sbatch hpc_maps.sbatch -c 18 $year-01-01 $year-12-31
