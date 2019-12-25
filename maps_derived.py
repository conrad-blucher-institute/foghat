#!/usr/bin/env python

import argparse
from netCDF4 import Dataset
import numpy as np

def specific_humidity(nc):
    """Given a NetCDF dataset, calculate mixing ratio for all desired pressure levels and save as new variables in the supplied dataset"""
    scratch = {}                        # temporary Numpy arrays/layers used for calculations
    # Loop over each desired pressure level (in millibars)
    for pres in range(700,1000+1,25):
        level = f'{pres}mb'             # label for NetCDF variable reference
        # For stauration vapor pressure (es), calculate
        #     temperature in C°
        temp_c = nc.variables[f'TMP_{level}'][:] - 273.15
        #     π  [exponent]
        pi = (17.67*temp_c) / (temp_c + 243.5)
        # Saturation vapor Pressure (es)
        es = 6.112*np.exp(pi)           # saturation vapor pressure at level l
        # Vapor Pressure (e)
        vap_pres = es*( nc.variables[f'RH_{level}'][:] / 100)
        # Mixing Ratio (mr)
        mr = ( (622*vap_pres) / (pres-vap_pres) )*1000
        # Specific Humidity (q)
        q = mr / (1+mr)
        scratch[f'Q_{level}'] = q
    # Calculate Specific Humidity (q) for the "surface"
    temp_c = nc.variables['TMP_2maboveground'][:] - 273.15
    # π  [exponent]
    pi = (17.67*temp_c) / (temp_c + 243.5)
    # Saturation vapor Pressure (es)
    es = 6.112*np.exp(pi)               # saturation vapor pressure at level l
    # Vapor Pressure (e)
    vap_pres = es*( nc.variables['RH_2maboveground'][:] / 100)
    # Mixing Ratio (mr)
    pres_mb = nc.variables['PRES_surface'][:] / 100 # Convert Pascals → mbar
    # XXX  Note the pressure in this calculation is gridded/an array, _not_ a scalar
    mr = ( (622*vap_pres)/(pres_mb - vap_pres) ) * 1000
    # Specific Humidity (q)
    q = mr / (1+mr)
    scratch[f'Q_surface'] = q

    print(scratch)


def process_file(filename):
    #nc = Dataset(filename, 'r')
    nc = Dataset(filename, 'a')
    x = nc.variables['x'][:]
    y = nc.variables['y'][:]

    print(x)
    print(y)
    # Looks like each of these is a list of 14 sublists, each containing the 14 latitudes/longitudes for those points
    latitude = nc.variables['latitude'][:]
    longitude = nc.variables['longitude'][:]
    #print(latitude)
    #print(longitude)

    times = nc.variables['time'][:]
    #nc.createVariable('DateVal', 'f', ('time'))
    #nc.createVariable('VAPE_850mb', 'f', ('time', 'x', 'y'))
    #print(times)

    nc_attrs = nc.ncattrs()
    for attr in nc_attrs:
        thing = nc.getncattr(attr)
        print(f'{attr} -> {thing}')

    # Dimension(s) of the NetCDF dataset?
    """
    print(nc.dimensions)
    nc_dims = [dim for dim in nc.dimensions]
    print(nc_dims)
    for label in nc_dims:
        obj = nc.dimensions[label]
        print(f'{obj.name}   {obj.size}')

    for var in nc.variables:
        print(f'Name: {var}')
        vobj = nc.variables[var]
        print(f'# of Dimensions: {vobj.ndim}')
        print(f'Dimensions: {vobj.dimensions}')
        print(f'size: {vobj.size}')
        print(f'shape: {vobj.shape}')

    #print(nc.variables['VIS_surface'])
    x = nc.variables['VIS_surface'][:]
    #print(x)
    print(x[0,0,0])
    print(x[0,0,1])
    print(x[0,1,1])
    #print(x*2)
    """

    # Time value for file in seconds since epoch (float)
    t = nc.variables['time'][:]
    print(t[0])

    # Add specific humidity derived variables to dataset
    specific_humidity(nc)
    # TODO  Add Lifted Condensation Level Temperature (LCL_T)s to dataset
    # TODO  Remove pressure at surface (PRES_surface) from dataset, as per Waylon
    # TODO  Add julian day calculation to dataset

    # TODO  Save/flush dataset to file


#process_file('maps_20180624_0000_007_input.nc')
parser = argparse.ArgumentParser()
parser.add_argument('file', help='NetCDF file to modify in place')
args = parser.parse_args()
if (args.file):
    process_file(args.file)
