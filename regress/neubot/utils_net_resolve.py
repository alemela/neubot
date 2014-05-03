#!/usr/bin/env python

#
# Copyright (c) 2014
#     Nexa Center for Internet & Society, Politecnico di Torino (DAUIN)
#     and Simone Basso <bassosimone@gmail.com>.
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

# Regression test for neubot/utils_net.py:resolve()

import logging
import sys

if __name__ == "__main__":
    sys.path.insert(0, ".")

from neubot import utils_net

def main():
    logging.basicConfig(level=logging.DEBUG, format="%(message)s")

    for family in ("PF_INET", "PF_INET6", "PF_UNSPEC", "PF_UNSPEC6",
                   True, False):
        for protocol in ("SOCK_STREAM", "SOCK_DGRAM"):
            utils_net.resolve(family, protocol, "www.youtube.com", "80", "")
            logging.debug("")

    for family in ("PF_INET", "PF_INET6", "PF_UNSPEC", "PF_UNSPEC6",
                   True, False):
        for protocol in ("SOCK_STREAM", "SOCK_DGRAM"):
            utils_net.resolve(family, protocol, None, "80", "AI_PASSIVE")
            logging.debug("")

if __name__ == "__main__":
    main()