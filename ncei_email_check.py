#!/usr/bin/env python

"""Retrieve NCEI Archive emails sent by NOAA w/ requested [NAM] archive data
download information and queue it for download

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

from imapclient import IMAPClient
from envparse import Env
# from lxml import etree                # Note 1

# See https://www.revsys.com/tidbits/python-12-factor-apps-envparse/
env = Env(
    FOGHAT_IMAP_HOST   = str,
    FOGHAT_IMAP_USER   = str,
    FOGHAT_IMAP_PASSWD = str
)

# Crude sanity check (envfile optional)
for v in ('FOGHAT_IMAP_HOST', 'FOGHAT_IMAP_USER', 'FOGHAT_IMAP_PASSWD'):
    assert env(v)

# Output log messages w/ [UTC] times in ISO 8601 format and host, program, pid too
logging.Formatter.converter = time.gmtime  # log message times in GMT/UTC
host = platform.uname().node            # cross-platform hostname
logging.basicConfig(format='#%(asctime)s {0} {1}[{2}] %(levelname)s:%(message)s'.format(host, os.path.basename(sys.argv[0]), os.getpid()), datefmt='%Y-%m-%dT%H:%M:%SZ')

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
"""

def main():
    uid2order = {}                      # email message id → AIRS order details

    # See code example from https://github.com/mjs/imapclient
    with IMAPClient(host=env('FOGHAT_IMAP_HOST'), use_uid=True) as server:
        server.login(env('FOGHAT_IMAP_USER'), env('FOGHAT_IMAP_PASSWD'))
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

    print(uid2order)  # XXX  REMOVE

    # TODO Check local store of queued jobs and filter pending/to be queued
    queue_orders = uid2order

    # Enqueue new orders
    for uid in queue_orders.keys():
        order_id = queue_orders[uid]['order_id']
        # [TaskSpooler] script.py uid  order_id  url
        cmd = ['ts/ts','./nam-archive-dl.sh',str(uid),order_id,queue_orders[uid]['url']]
        #ts_proc = subprocess.run(['ts/ts','./nam-archive-dl.sh',str(uid),queue_orders[uid]['order_id'],queue_orders[uid]['url']], capture_output=True)
        ts_proc = subprocess.run(cmd,capture_output=True)
        if ts_proc.returncode == 0:
            jobid=ts_proc.stdout.decode().rstrip()
            print('Enqueued download of order ID {} as Task Spooler job #{}'.format(order_id,jobid))
            # TODO  Add queue_orders[uid] to local store orders
        else:
            print('Error occurred when trying to run subprocess {}'.format(' '.join(cmd)))
            print(ts_proc)

    # TODO Write out updated queued jobs store


if __name__ == "__main__":
    # TODO  Verify no other instance of this program is running?
    main()
