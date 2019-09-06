Fog Prediction System Notes
===========================

Download data that we _might_ use for [development of] operational Fog prediction system.

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

