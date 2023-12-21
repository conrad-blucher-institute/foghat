Fog Prediction System Notes
===========================

Download and prepare data for research [Fog prediction system](https://github.com/conrad-blucher-institute/FogNet).

For more information, please visit https://gridftp.tamucc.edu/fognet/

Setup
-----
No matter where you're running this code, you'll need to configure/customize the environment [configuration] variables.

Copy the sample environment variable file in `etc/` and modify as necessary for the specific host you're running these scripts on:

```
cp etc/sample-environment.sh  etc/foghat_config.sh
vi etc/foghat_config.sh
```

Be sure to source the environment variable file before running the scripts!  E.g., `. etc/foghat_config.sh`

Since all the environment variables are prefixed with `FOGHAT_`, it should be safe to add that source command to your `~/.bashrc` to automatically do this when you login.

TAMUCC HPC Setup
----------------
You only need to do the following steps once, but you need to do it _before_ trying to run any of the processing jobs or else they will fail.

### Slurm Batch scripts

Copy the sample Slurm Batch script (`.sbatch`) to `hpc_maps.sbatch` and customize it:

```
cp hpc_maps.sbatch-sample hpc_maps.sbatch
cp hpc_tarball.sbatch-sample hpc_tarball.sbatch
```

For *both* the `hpc_maps.sbatch` and `hpc_tarball.sbatch` files, modify the following lines (add your email address) so _you_ can be notified when a job finishes:
```
## XXX  If you want to be notified when your job ends/fails, change the following two lines
##SBATCH --mail-type=END,FAIL            # Mail events (NONE, BEGIN, END, FAIL, ALL)
##SBATCH --mail-user=example@tamucc.edu   # Where to send mail
```

Make sure there is only _one_ pound sign (`#`) in front of the modified `SBATCH` directives:
```
## XXX  If you want to be notified when your job ends/fails, change the following two lines
#SBATCH --mail-type=END,FAIL            # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --mail-user=firstname.lastname@tamucc.edu     # Where to send mail
```

### Python Environment Setup

1. Login to the HPC.

2. Load the Python Slurm module:
```
module load python3/gcc7/3.7.4
```

3. Create your virtual environment for foghat:
```
python3 -m venv ~/venv/foghat
source ~/venv/foghat/bin/activate
pip install -r requirements.txt
```

If the python modules install correctly, you're good to go!


Processing Data
---------------

Finally, to process data on the TAMUCC HPC, the easiest way is to run the shell script which will queue jobs to process a single year and if the processing jobs complete successfully, create a tarball w/ all the data for that year.  E.g.,

```
. ~/etc/foghat_config.sh
./queue_hpc_1year.sh 2020
```

You only need to source the `foghat_config.sh` file if you haven't already loaded those environment variables.


Other Notes / Details
=====================

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
