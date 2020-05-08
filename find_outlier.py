#!/usr/bin/env python3

"""
Find NetCDF "filled values" in DQDZ1000SFC and DQDZ700725 derived
parameters in the generated input files (produced by maps_input.sh and
maps_derived.py).
"""

import os
import argparse
import re
from netCDF4 import Dataset
import numpy as np

def process_file(filename):
    nc = Dataset(filename, 'r')
    m = re.search('maps_(\d+)_(\d+)_(\d+)_input.nc$', filename)
    if not m:                           # wrong filename, skip
        return
    strs = []
    strs.append(f'{m[0]},{m[1]},{m[2]},{m[3]}') # file information
    for label in ('DQDZ1000SFC', 'DQDZ700725'):
        var = nc.variables[label][:]
        min = var.data.min()
        max = var.data.max()
        oob = np.count_nonzero(var.data > 9999)
        strs.append(f'{min},{max},{oob}')
    print(','.join(strs))

def process_folder(folder, limit=0):
    for dirpath, dirnames, filenames in os.walk(folder):
        count = 0
        for f in filenames:
            fqpn = os.path.join(dirpath, f)
            process_file(fqpn)
            count += 1
            if limit and count >= limit:
                return

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', help='Folder containing NetCDF files to check')
    parser.add_argument('--limit', help='Only process limit number of files', type=int)
    args = parser.parse_args()
    if args.folder:
        process_folder(args.folder, args.limit)
