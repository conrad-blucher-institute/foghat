
# Resaonable default HPC settings

export FOGHAT_BASE=/work/TANN/fog-data
export FOGHAT_ARCHIVE_DIR=$FOGHAT_BASE/archive
export FOGHAT_COOKIES=$HOME/.cookies
export FOGHAT_EXE_DIR=$HOME/git/foghat

# Slightly confusing, but where to store generated model input files
export FOGHAT_INPUT_DIR=/work/TANN/$USER/fog
# Logs from data processing should be stored in user-specific work directory
export FOGHAT_LOG_DIR=/work/TANN/$USER/logs
