
export FOGHAT_BASE=$HOME/fog-data
export FOGHAT_LOG_DIR=$FOGHAT_BASE/logs
export FOGHAT_ARCHIVE_DIR=$FOGHAT_BASE/archive
export FOGHAT_COOKIES=$FOGHAT_BASE/.cookies

# Only need these on server that's involved in NAM requests/downloads
export FOGHAT_IMAP_HOST='imap.gmail.com'
export FOGHAT_IMAP_USER='username'
export FOGHAT_IMAP_PASSWD='password'

# Only needed for server running Task Spooler (same as above)
# man ts/ts.1  for environment variable description
export TS_SLOTS=2
export TS_SAVELIST=$HOME/.foghat_spooler

# Make sure email has HTML entities encoded  (@ → %40)
export FOGHAT_EMAIL='username%40gmail.com'
