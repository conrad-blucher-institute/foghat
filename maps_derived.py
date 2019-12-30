#!/usr/bin/env python

import argparse
import time
import math
from netCDF4 import Dataset
import numpy as np

def specific_humidity(nc):
    """Given a NetCDF dataset, calculate mixing ratio for all desired
       pressure levels and save as new variables in the supplied dataset
    """
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

    # We want Specific Humidity (q) at surface in dataset, I believe
    qsfc = nc.createVariable('Q_surface', 'f', ('time','x','y'))
    qsfc[:] = q
    qsfc.long_name = 'Specific humidity (q) at surface'
    qsfc.short_name = 'Q_surface'

    # Add DeltaQ* variables to NetCDF dataset/file
    qsfc1000 = nc.createVariable('DeltaQSFC1000', 'f', ('time','x','y'))
    qsfc1000[:] = scratch['Q_surface'] - scratch['Q_1000mb']
    qsfc1000.long_name = f'Delta of specific humidity (q) between surface and 1000mb'
    qsfc1000.short_name = 'DeltaQSFC1000'

    for minuend in range(1000, 725-1, -25):
        sub = minuend - 25              # subtrahend
        name = f'DeltaQ{minuend}{sub}'
        q_delta = nc.createVariable(name, 'f', ('time','x','y'))
        q_delta[:] = scratch[f'Q_{minuend}mb'] - scratch[f'Q_{sub}mb']
        q_delta.long_name = f'Delta of specific humidity (q) between {minuend}mb and {sub}mb'
        q_delta.short_name = name


def lclt(nc):
    """Given a NetCDF dataset, calculate lifted condensation level
       temperature (LCL_T) [at surface?] and save as new variables in
       the supplied dataset
    """
    denominator = 1/(nc.variables['TMP_2maboveground'][:] - 55) - np.log(nc.variables['RH_2maboveground'][:] / 100)
    temp = 1/denominator + 55
    lcl_t = nc.createVariable('LCLT', 'f', ('time','x','y'))
    lcl_t[:] = temp
    lcl_t.long_name = 'Lifted Condensation Level Temperature'
    lcl_t.short_name = 'LCL_T'
    lcl_t.units = 'Kelvin'


def dateval(nc):
    """Given a NetCDF dataset, calculate the DateVal(t) function for
       the time of day the predictions _represent_ (model cycle time
       + forecast hour) and save as a new variable in the supplied
       dataset.

       This is used to tell the model what time of year it is.
    """
    # Model cycle time + Forecast hour time value in seconds since epoch (float)
    gmt = nc.variables['time'][:][0]
    # Julian Day for above ([1,366] → [0,365])
    doy = time.gmtime(gmt).tm_yday - 1
    dateval = (math.sin(math.pi*doy/365))**2
    dv = nc.createVariable('DateVal', 'f', ('time'))
    dv[:] = dateval
    dv.long_name = 'Date Value (sine of Julian Day)'
    dv.short_name = 'DateVal'


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

    # Add specific humidity derived variables to dataset
    specific_humidity(nc)
    # Add Lifted Condensation Level Temperature (LCL_T)s to dataset
    lclt(nc)
    # Add DateVal (sine of Julian day) to dataset
    dateval(nc)

    # TODO  Remove pressure at surface (PRES_surface) from dataset, as per Waylon

    # TODO  Save/flush dataset to file
    print(nc.History)

# TODO  Wrap in __main__ function

#process_file('maps_20180624_0000_007_input.nc')
parser = argparse.ArgumentParser()
parser.add_argument('file', help='NetCDF file to modify in place')
args = parser.parse_args()
if (args.file):
    process_file(args.file)
