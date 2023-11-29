
export FOGHAT_BASE=$HOME/fog-data
export FOGHAT_LOG_DIR=$FOGHAT_BASE/logs
export FOGHAT_ARCHIVE_DIR=$FOGHAT_BASE/archive
export FOGHAT_COOKIES=$HOME/.cookies

# Additional options for all wget invocations
# I use this for network bandwidth utilization / server "niceness" and hopefully to not get IP/server banned by NOAA
# FMI https://www.gnu.org/software/wget/manual/html_node/Download-Options.html
#export FOGHAT_WGET_OPTIONS="--limit-rate=10m --wait=5"

# Only need these on server that's involved in NAM requests/downloads
export FOGHAT_IMAP_HOST='imap.gmail.com'
export FOGHAT_IMAP_USER='username'
export FOGHAT_IMAP_PASSWD='password'

# Send ncei_email.py logging output to file instead of stderr
export FOGHAT_LOGGER2FILE=1

# Only needed for server running Task Spooler (same as above)
# man ts/ts.1  for environment variable description
export TS_SLOTS=2
export TS_SAVELIST=$HOME/.foghat_spooler

# Make sure email has HTML entities encoded  (@ → %40)
export FOGHAT_EMAIL='username%40gmail.com'

# Slightly confusing, but where to store generated model input files
export FOGHAT_INPUT_DIR=$FOGHAT_BASE/input
export FOGHAT_EXE_DIR=$HOME/git/foghat

# Send notification emails to this person (mailx)
export FOGHAT_NOTIFY_EMAIL='username@hostname.com'
