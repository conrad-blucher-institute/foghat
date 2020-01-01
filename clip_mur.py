#!/usr/bin/env python3

# I _was_ going to have this code clip the NetCDF file but that was
# before I realized ncks can accept latitude,longitude ranges instead of
# just indices.  ¯\_(ツ)_/¯
#
#  At least I didn't get too far into writing it :)

import argparse
from netCDF4 import Dataset
import numpy as np

def clip(filename):
    nc = Dataset(filename, 'r')

    # Code stolen/adapted from https://stackoverflow.com/a/29136166/1502174

    # Hamid's MapS DLNN bounding box
    latbounds = [ 27 , 28.5 ]
    lonbounds = [ -97.7 , -96 ] # degrees east

    lats = nc.variables['lat'][:]
    lons = nc.variables['lon'][:]

    # latitude lower and upper index
    latli = np.argmin( np.abs( lats - latbounds[0] ) )
    latui = np.argmin( np.abs( lats - latbounds[1] ) )

    # longitude lower and upper index
    lonli = np.argmin( np.abs( lons - lonbounds[0] ) )
    lonui = np.argmin( np.abs( lons - lonbounds[1] ) )

    # Actual latitude/longitude values for ncks _must_ include decimal point
    # FMI see https://stackoverflow.com/a/25751550/1502174
    latbounds_str = ','.join([str(float(x)) for x in latbounds])
    lonbounds_str = ','.join([str(float(x)) for x in lonbounds])

    # KISS
    print(f'For latitude range [{latbounds_str}] and longitude range [{lonbounds_str}] in file {filename}:')
    print(f' • Latitude indexes are [{latli}, {latui}], longitude indexes are [{lonli},{lonui}]')
    print(f'ncks command invocations to crop this file:')
    print(f' • ncks --no_alphabetize -d lat,{latbounds_str} -d lon,{lonbounds_str} {filename} -O range_example.nc')
    print(f' • ncks --no_alphabetize -d lat,{latli},{latui} -d lon,{lonli},{lonui} {filename} -O index_example.nc')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('file', help='NetCDF file to modify in place')
    args = parser.parse_args()
    if args.file:
        clip(args.file)
