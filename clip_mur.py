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

    # Hamid's [expanded] MapS DLNN bounding box
    latbounds = [ 25.74 , 29.5 ]
    lonbounds = [ -97.77 , -94 ] # degrees east

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
    print(f' • ncks --no_alphabetize -d lat,{latli},{latui} -d lon,{lonli},{lonui} {filename} -O index_example.nc\n')

    print(f'From the NetCDF file, latitude bounds {lats[latli]:.6f},{lats[latui]:.6f} ; longitude bounds {lons[lonli]:.6f},{lons[lonui]:.6f}')
    print(f' • resulting grid dimensions {latui-latli} latitude, {lonui-lonli} longitude')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('file', help='NetCDF file to examine WRT latitude, longitude')
    args = parser.parse_args()
    if args.file:
        clip(args.file)
