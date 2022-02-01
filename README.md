Fog Prediction System Notes
===========================

Download and prepare data for research [Fog prediction system](https://github.com/conrad-blucher-institute/FogNet).

For more information, please visit https://gridftp.tamucc.edu/fognet/

Setup
-----

Copy the sample environment variable file in `etc/` and modify as necessary for the specific host you're running these scripts on:

```
cp etc/sample-environment.sh  etc/foghat_config.sh
vi etc/foghat_config.sh
```

Be sure to source the environment variable file before running the scripts!  E.g., `. etc/foghat_config.sh`

Since all the environment variables are prefixed with `FOGHAT_`, it should be safe to add that source command to your `~/.bashrc` to automatically do this when you login.


Regular Sources
---------------

Regular data retrievals (repeated anything more than a few times) should be scripted for consistency and to make it easier to add other systems (redundancy) to the pool that is downloading data.

So far I've done this, including a `rsync` from TAMUCC HPC storage to `$local_machine`.  The HPC storage _should_ be--typically--the master/authoritative repository.


wget Example
------------

Example `wget` command for download all files from Matthew Pyle's temporary download site into current directory:

    cd ~/mpyle-vis/
    wget -nv --no-parent -r --limit-rate=5m --wait=5 --timestamping --append-output=dl_log.txt -nd ftp://ftp.emc.ncep.noaa.gov/mmb/WRFtesting/mpyle/vis_tmp/

Best to run something like the above w/in a `tmux` session


netCDF Files
------------

If this system will be preparing netCDF files for DLNN input, you need to prepare the OS environment before installing python requirements.

- Centos: make sure to `yum install netcdf-devel` _before_ `pip install netCDF4` (in the appropriate virtual environment)
