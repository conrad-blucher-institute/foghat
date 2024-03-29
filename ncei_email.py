#!/usr/bin/env python

"""Retrieve NCEI Archive emails sent by NOAA w/ requested [NAM] archive data
download information and queue it for download.  I'm assuming the IMAP email
is a gmail address or at least compatible w/ the Gmail extensions of
IMAPClient

This script runs on gridftp, which is running CentOS 6.10 and Python v3.4.10.
Compromises (e.g., libraries, language features) have been made.
"""

import email
import re
import logging
import os
import sys
import time
import platform
import subprocess
from subprocess import CalledProcessError, SubprocessError
import argparse

from imapclient import IMAPClient
from envparse import Env
# from lxml import etree                # Note 1

# See https://www.revsys.com/tidbits/python-12-factor-apps-envparse/
env = Env(
    FOGHAT_IMAP_HOST   = str,
    FOGHAT_IMAP_USER   = str,
    FOGHAT_IMAP_PASSWD = str,
    FOGHAT_LOG_DIR     = str
)
# I don't know how to specify a default for primitive types in the above format
logger_openfile = env.bool('FOGHAT_LOGGER2FILE', default=False) # Note 5

# Crude sanity check (envfile optional)
for v in ('FOGHAT_IMAP_HOST', 'FOGHAT_IMAP_USER', 'FOGHAT_IMAP_PASSWD', 'FOGHAT_LOG_DIR'):
    assert env(v)

# Output log messages w/ [UTC] times in ISO 8601 format and host, program, pid too
logging.Formatter.converter = time.gmtime  # log message times in GMT/UTC
host = platform.uname().node            # cross-platform hostname
logging_kwargs = dict(format='#%(asctime)s {0} {1}[{2}] %(levelname)s:%(message)s'.format(host, os.path.basename(sys.argv[0]), os.getpid()), datefmt='%Y-%m-%dT%H:%M:%SZ')
logfn = '{}/ncei_email-{}.log'.format(env('FOGHAT_LOG_DIR'), time.strftime("%Y%m%d", time.gmtime()))

try:
    if logger_openfile:
        logging_kwargs['filename'] = logfn
        logging_kwargs['filemode'] = 'a'
    logging.basicConfig(**logging_kwargs)
except OSError as e:
    print(e, file=sys.stderr)
    print("Error when trying to setup logger object, is HPC storage ({}) offline/disconnected?  Giving up".format(env('FOGHAT_LOG_DIR')), file=sys.stderr)
    exit(1)

logger = logging.getLogger(__name__)
#logger.setLevel(logging.INFO)
logger.setLevel(logging.DEBUG)  # XXX  REMOVE

"""NOTES

  1.  The Xpath to Web Download URL in email is:

      //*[@id="items"]/table/tbody/tr[2]/td[2]/a

      Using regex b/c lxml library requires Python 3.5+ :(

  2.  Task Spooler <https://vicerveza.homeunix.net/~viric/soft/ts/>
      inherits any local environment settings when the job is queued.
      So we don't need to load the foghat environment variables or the
      python virtual environment--that's already done.

  3.  Can't use subprocess.run() b/c Python 3.4

  4.  Adapted from https://chase-seibert.github.io/blog/2014/03/21/python-multilevel-argparse.html

  5.  I _was_ going to make logging to a file a CLI option but given the
      current way I'm using argparse w/ list slice, I'll have to manually
      detect presence of the optional --log argument in main(), adjust the
      slice range ([1:2] → [1:3] or somesuch) _and_ adjust the slice range
      of the parse_args() in the dispatched function (check or move).
      Easier to make it mandatory
"""

def check(server):
    """Check inbox for new emails from NOAA [AIRS Orders] and queue them for processing"""
    uid2order = {}                      # email message id → AIRS order details

    exe = os.path.basename(sys.argv[0])
    parser = argparse.ArgumentParser(prog='{} check'.format(exe),description='Check inbox for new emails from NOAA [AIRS Orders] and queue for processing')
    parser.add_argument('--dry-run',action='store_true',help="Don't actually begin processing, just say what would be done")
    args = parser.parse_args(sys.argv[2:])
    select_info = server.select_folder('INBOX')
    messages = server.search(['FROM','noreply@noaa.gov'])
    logger.info('{} messages in INBOX, {} from NOAA'.format(select_info[b'EXISTS'], len(messages)))
    if len(messages) == 0:
        logger.info('No order complete [data ready] messages, quitting')
        return

    # Filter messages from NOAA
    for uid, data in server.fetch(messages, ['ENVELOPE']).items():
        envelope = data[b'ENVELOPE']
        subject = envelope.subject.decode()
        from_addr = '{}'.format(envelope.from_[0])
        logger.info('ID #{} {} "{}", received {} CST/CDT'.format(uid, from_addr, subject, envelope.date))
        # Search for order ID in email subject
        m = re.search(r'Order (\w+) Complete', subject)
        if not m:
            logger.error("Can't locate order ID in email #{}'s subject \"{}\", skipping".format(uid, subject))
            continue
        order_id = m.group(1)
        uid2order[uid] = { 'order_id': order_id, 'from': from_addr }

    airs_uids = uid2order.keys()
    for uid, message_data in server.fetch(airs_uids, 'RFC822').items():
        email_message = email.message_from_bytes(message_data[b'RFC822'])
        logger.info('Opening email ID #{} {} "{}"'.format(uid, uid2order[uid]['from'], email_message.get('Subject')))
        urls = []
        for part in email_message.walk():
            mt = part.get_content_type()
            if mt == 'text/plain' or mt == 'text/html':
                txt = part.get_payload()
                # Note 1
                matches = re.findall(r'"(https://[^"]*/pub/has/[^"]+)"', txt)
                urls.extend(matches)
        # Make sure we only found _one_ download link
        if len(urls) != 1:
            logger.error("Unexpected number {} of matching web download URLs in email for order ID {}, skipping".format(len(urls), order_id))
            logger.debug(urls)
            continue
        uid2order[uid]['url'] = urls[0]
    #print(uid2order)  # XXX  REMOVE

    # TODO Check local store of queued jobs and filter pending/to be queued
    queue_orders = uid2order

    # TODO  Check local store for jobs that can be removed (b/c email has been Archived)

    # Enqueue new orders
    for uid in queue_orders.keys():
        order_id = queue_orders[uid]['order_id']
        # [TaskSpooler] script.py uid  order_id  url
        cmd = ['ts/ts','./nam-archive-dl.sh',str(uid),order_id,queue_orders[uid]['url']]
        try:
            if args.dry_run:
                logger.info('Would run command « {} »'.format(' '.join(cmd)))
                jobid = -1
            else:
                # Note 3
                jobid = subprocess.check_output(cmd).decode().rstrip()
                pass
        except (CalledProcessError, SubprocessError) as err:
            logger.error('Error [return] code {} returned when trying to run subprocess {}'.format(err.returncode,' '.join(cmd)))
            logger.error(err.output)
        logger.info('Enqueued download of order ID {} as Task Spooler job #{}'.format(order_id,jobid))

    # Move queued email jobs to different folder (state change)
    if not args.dry_run:
        server.move(messages=queue_orders.keys(), folder='Queued')
    uids_str = ','.join([ str(k) for k in queue_orders.keys() ])
    logger.info('Moved email(s) w/ UID(s) [{}] to Queued folder'.format(uids_str))

    # TODO Write out updated queued jobs store

def move(server):
    parser = argparse.ArgumentParser(description='Move specified email (by Order ID) to specified folder')
    parser.add_argument('order', type=str, help='AIRS Order ID')
    parser.add_argument('source', type=str, help='Current folder name containing email')
    parser.add_argument('destination', type=str, help='Destination folder name (or Archive)')
    args = parser.parse_args(sys.argv[2:])
    select_info = server.select_folder(args.source)
    subject = 'AIRS Order {} Complete'.format(args.order)
    uids = server.search(['FROM','noreply@noaa.gov','SUBJECT',subject])
    # Make sure we only found _one_ matching email
    if len(uids) != 1:
        logger.error("Can't find email w/ Order ID {} in folder {}".format(args.order,args.source))
        return
    logger.info("Moving email w/ Order ID {} (UID #{}) into folder {}".format(args.order, uids[0], args.destination))
    server.move(messages=uids, folder=args.destination)

def main():

    # Process CLI args and dispatch appropriately
    # Note 4
    parser = argparse.ArgumentParser(description='Interact with email account via IMAP to handle NOAA archive data orders.',
        usage='''%(prog)s <command> [<args>]

Where command is one of:
   check    Check email for new AIRS Orders to download
   move     Move email to a different [email system] folder
''')
    parser.add_argument('command', help='Subcommand to run')
    # Note 5
    # parse_args defaults to [1:] for args, but you need to
    # exclude the rest of the args too, or validation will fail
    args = parser.parse_args(sys.argv[1:2])
    if not args.command in func_name_dict.keys() :
        print('Unrecognized command: {}'.format(args.command))
        parser.print_help()
        exit(1)
    # See code example from https://github.com/mjs/imapclient
    server = IMAPClient(host=env('FOGHAT_IMAP_HOST'), use_uid=True)
    server.login(env('FOGHAT_IMAP_USER'), env('FOGHAT_IMAP_PASSWD'))
    # use dispatch pattern to invoke method with same name
    dispatch(args.command, server)
    server.logout()
    logging.shutdown()

# Adapted from https://stackoverflow.com/a/36270394/1502174
func_name_dict = {
    'check': check,
    'move': move
}

def dispatch(name, *args, **kwargs):
    func_name_dict[name](*args, **kwargs)

if __name__ == "__main__":
    # TODO  Verify no other instance of this program is running?
    main()
