Fog Prediction System Notes
===========================

Download data that we _might_ use for [development of] operational Fog prediction system.

HREF [Visibility] Archive
-------------------------

Example `wget` command for download all files from Matthew Pyle's temporary download site into current directory:

    cd ~/mpyle-vis/
    wget -nv --no-parent -r --limit-rate=5m --wait=5 --timestamping --append-output=dl_log.txt -nd ftp://ftp.emc.ncep.noaa.gov/mmb/WRFtesting/mpyle/vis_tmp/

Best to run something like the above w/in a `tmux` session

