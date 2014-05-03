# neubot/stream.py

#
# Copyright (c) 2010-2012 Simone Basso <bassosimone@gmail.com>,
#  NEXA Center for Internet & Society at Politecnico di Torino
#
# This file is part of Neubot <http://www.neubot.org/>.
#
# Neubot is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Neubot is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Neubot.  If not, see <http://www.gnu.org/licenses/>.
#

''' Pollable socket stream '''

# Python3-ready: yes

import logging
import os

from neubot.defer import Deferred
from neubot.pollable import Pollable
from neubot.poller import POLLER

from neubot.pollable import CONNRESET
from neubot.pollable import SUCCESS
from neubot.pollable import SocketWrapper
from neubot.pollable import WANT_READ
from neubot.pollable import WANT_WRITE

from neubot import utils_net
from neubot import six

EMPTY_STRING = six.b('')

class StreamWrapperDebug(SocketWrapper):
    ''' Debug stream wrapper '''

    def sorecv(self, maxlen):
        maxlen = 1
        return SocketWrapper.sorecv(self, maxlen)

def _stream_wrapper(sock):
    ''' Create the right stream wrapper '''
    if not os.environ.get('NEUBOT_STREAM_DEBUG'):
        return SocketWrapper(sock)
    logging.warning('stream: creating debug stream: performance will suck')
    return StreamWrapperDebug(sock)

class Stream(Pollable):

    ''' A pollable stream socket '''

    #
    # Init path: register connection_made() and connection_lost() callbacks,
    # and eventually configure SSL.  Note that this class routes the calls
    # to another class, so the protocol does not need to subclass this class,
    # reducing explict code dependency.
    #

    def __init__(self, sock, connection_made, connection_lost, sslconfig,
                 sslcert, opaque):
        Pollable.__init__(self)

        self.poller = POLLER
        self.filenum = sock.fileno()
        self.myname = utils_net.getsockname(sock)
        self.peername = utils_net.getpeername(sock)
        self.logname = '%s %s' % (utils_net.format_epnt(self.myname),
                                  utils_net.format_epnt(self.peername))

        logging.debug('stream: __init__(): %s', self.logname)

        # Variables pointing to other objects
        self.atclose = Deferred()
        self.atconnect = Deferred()
        self.opaque = opaque
        self.recv_complete = None
        self.send_complete = None
        self.send_octets = EMPTY_STRING
        self.sock = None

        # Variables we don't need to clear
        self.bytes_in = 0
        self.bytes_out = 0
        self.conn_rst = False
        self.eof = False
        self.isclosed = False
        self.recv_count = 0
        self.recv_blocked = False
        self.send_blocked = False

        self.atclose.add_callback(connection_lost)
        self.atconnect.add_callback(connection_made)
        self.atconnect.add_errback(self._connection_made_error)

        if not sslconfig:
            self.sock = _stream_wrapper(sock)
            self.atconnect.callback(self)
            return

        #
        # Lazy import: this fails on Python 2.5, because SSL is not part of
        # v2.5 standard library.  We do not intercept the error here, because
        # accept() code already needs to setup a try..except to route any
        # error away from the listening socket.
        #
        from neubot import sslstream

        #
        # If there is SSL support, initialise() deals transparently with SSL
        # negotiation, and invokes connection_made() when done.  Errors are
        # routed to the POLLER, which generates CLOSE events accordingly.
        #
        sslstream.initialise(self, sock, sslcert)

    def _connection_made_error(self, exception):
        ''' Invoked when connection_made() callback fails '''
        logging.warning('stream: connection_made() failed: %s', str(exception))
        self.poller.close(self)

    #
    # Close path: the close() function simply tells the poller to generate
    # the handle_close() event, the handle_close() function is reentrant and
    # invokes the registered callback functions.
    #

    def register_cleanup(self, func):
        ''' Register a cleanup function '''
        self.atclose.add_callback(func)

    def close(self):
        ''' Close the stream '''
        self.poller.close(self)

    def handle_close(self):

        if self.isclosed:
            return

        logging.debug('stream: closing %s', self.logname)
        self.isclosed = True

        self.atclose.callback_each_np(self)
        self.sock.close()

        self.atclose = None
        self.atconnect = None
        self.opaque = None
        self.recv_complete = None
        self.send_complete = None
        self.send_octets = None
        self.sock = None

    def __del__(self):
        logging.debug('stream: __del__(): %s', self.logname)

    #
    # Receive path: the protocol invokes recv() to start an async recv()
    # operation, the poller invokes handle_read() when the socket becomes
    # readbable, handle_read() invokes recv_complete() when the recv()
    # is complete.
    #

    def recv(self, recv_count, recv_complete):
        ''' Async recv() '''

        if self.isclosed:
            raise RuntimeError('stream: recv() on a closed stream')
        if self.recv_count > 0:
            raise RuntimeError('stream: already recv()ing')
        if recv_count <= 0:
            raise RuntimeError('stream: invalid recv_count')

        self.recv_count = recv_count
        self.recv_complete = recv_complete

        if self.recv_blocked:
            logging.debug('stream: recv() is blocked')
            return

        self.poller.set_readable(self)

    def handle_read(self):

        if self.recv_blocked:
            self.poller.set_writable(self)
            if self.recv_count <= 0:
                self.poller.unset_readable(self)
            self.recv_blocked = False
            self.handle_write()
            return

        status, octets = self.sock.sorecv(self.recv_count)

        if status == SUCCESS and octets:
            self.recv_count = 0
            self.poller.unset_readable(self)
            self.on_data(octets)
            return

        if status == WANT_READ:
            return

        if status == WANT_WRITE:
            self.poller.unset_readable(self)
            self.poller.set_writable(self)
            self.send_blocked = True
            return

        if status == SUCCESS and not octets:
            self.on_eof()
            self.poller.close(self)
            return

        if status == CONNRESET and not octets:
            self.on_rst()
            self.poller.close(self)
            return

        raise RuntimeError('stream: invalid status')

    def on_data(self, octets):
        self.bytes_in += len(octets)
        self.recv_complete(self, octets)

    def on_eof(self):
        self.eof = True

    def on_rst(self):
        self.conn_rst = True

    #
    # Send path: the protocol invokes start send to start an async send()
    # operation, the poller invokes handle_write() when the underlying socket
    # becomes writable, handle_write() invokes send_complete() when send()
    # is complete.
    #

    def send(self, send_octets, send_complete):
        ''' Async send() '''

        if self.isclosed:
            raise RuntimeError('stream: send() on a closed stream')
        if self.send_octets:
            raise RuntimeError('stream: already send()ing')

        self.send_octets = send_octets
        self.send_complete = send_complete

        if self.send_blocked:
            logging.debug('stream: send() is blocked')
            return

        self.poller.set_writable(self)

    def handle_write(self):

        #
        # Deal with the case where send() is blocked by recv(), that happens
        # when we are using SSL and recv() returned WANT_WRITE.  In the common
        # case, this costs just one extra if in the fast path.
        #
        if self.send_blocked:
            logging.debug('stream: handle_write() => handle_read()')
            self.poller.set_readable(self)
            if not self.send_octets:
                self.poller.unset_writable(self)
            self.send_blocked = False
            self.handle_read()
            return

        status, count = self.sock.sosend(self.send_octets)

        #
        # Optimisation: reorder if branches such that the ones more relevant
        # for better performance come first.  Testing in early 2011 showed that
        # this arrangement allows to gain a little more speed.  (And the code
        # is still readable.)
        #

        if status == SUCCESS and count > 0:
            self.bytes_out += count

            if count == len(self.send_octets):
                self.poller.unset_writable(self)
                self.send_octets = EMPTY_STRING
                self.send_complete(self)
                return

            if count < len(self.send_octets):
                self.send_octets = six.buff(self.send_octets, count)
                return

            raise RuntimeError('stream: invalid count')

        if status == WANT_WRITE:
            return

        if status == WANT_READ:
            logging.debug('stream: blocking recv()')
            self.poller.unset_writable(self)
            self.poller.set_readable(self)
            self.recv_blocked = True
            return

        if status == CONNRESET and count == 0:
            logging.debug('stream: RST')
            self.conn_rst = True
            self.poller.close(self)
            return

        if status == SUCCESS and count < 0:
            raise RuntimeError('stream: negative count')

        raise RuntimeError('stream: invalid status')

    #
    # Miscellaneous functions
    #

    def __repr__(self):
        return self.logname

    def fileno(self):
        return self.filenum
