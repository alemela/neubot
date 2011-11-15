# Makefile

#
# Copyright (c) 2010-2011 Simone Basso <bassosimone@gmail.com>,
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

#
# The scripts/release script will automatically update the
# version number each time we tag with a new release.
#
VERSION	= 0.4.4

#
# The list of .PHONY targets.  This is also used to build the
# help message--and note that the targets named with a leading
# underscore are private.
# Here we list targets in file order because this makes it easier
# to maintain this list.
#
PHONIES += help
PHONIES += clean
PHONIES += archive
PHONIES += _install
PHONIES += install
PHONIES += uninstall
PHONIES += _deb_data
PHONIES += _deb_data.tgz
PHONIES += _deb_control_skel
PHONIES += _deb_control_md5sums
PHONIES += _deb_control_size
PHONIES += _deb_control
PHONIES += _deb_control.tgz
PHONIES += _deb_binary
PHONIES += _deb
PHONIES += deb
PHONIES += release

.PHONY: $(PHONIES)

help:
	@printf "Targets:"
	@for TARGET in `grep ^PHONIES Makefile|sed 's/^.*+= //'`; do	\
	     if echo $$TARGET|grep -qv ^_; then				\
	         printf " $$TARGET";					\
	     fi;							\
	 done
	@printf '\n'
clean:
	@echo "[CLEAN]"
	@./scripts/cleanup

#                 _     _
#   __ _ _ __ ___| |__ (_)_   _____
#  / _` | '__/ __| '_ \| \ \ / / _ \
# | (_| | | | (__| | | | |\ V /  __/
#  \__,_|_|  \___|_| |_|_| \_/ \___|
#
# Create source archives
#

STEM = neubot-$(VERSION)
ARCHIVE = git archive --prefix=$(STEM)/

archive:
	@echo "[ARCHIVE]"
	@install -d dist/
	@for FMT in tar zip; do \
	 $(ARCHIVE) --format=$$FMT HEAD > dist/$(STEM).$$FMT; \
	done
	@gzip -9 dist/$(STEM).tar

#  _           _        _ _
# (_)_ __  ___| |_ __ _| | |
# | | '_ \/ __| __/ _` | | |
# | | | | \__ \ || (_| | | |
# |_|_| |_|___/\__\__,_|_|_|
#
# Install neubot in the filesystem
#

#
# We need to override INSTALL with 'install -o 0 -g 0' when
# we install from sources because in this case we want to
# enforce root's ownership.
#
INSTALL	= install

#
# These are some of the variables accepted by the GNU
# build system, in order to follow the rule of the least
# surprise [1].
# We install neubot in $(DATADIR)/neubot following sect.
# 3.1.1 of Debian Python Policy which covers the shipping
# of private modules [2].
# We follow BSD hier(7) and we install manual pages in
# /usr/local/man by default.
#
# [1] http://bit.ly/aLduJz (gnu.org)
# [2] http://bit.ly/ayYyAR (debian.org)
#
DESTDIR =
SYSCONFDIR = /etc
LOCALSTATEDIR = /var/neubot
PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
DATADIR = $(PREFIX)/share
MANDIR = $(PREFIX)/man

_install:
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL) bin/neubot $(DESTDIR)$(BINDIR)/neubot
	$(INSTALL) -d $(DESTDIR)$(DATADIR)
	for DIR in `cd UNIX/share && find . -type d -mindepth 1`; do \
	    $(INSTALL) -d $(DESTDIR)$(DATADIR)/$$DIR; \
	    test $$? || exit 1; \
	done
	for FILE in `cd UNIX/share && find . -type f`; do \
	    $(INSTALL) -m644 UNIX/share/$$FILE $(DESTDIR)$(DATADIR)/$$FILE; \
	    test $$? || exit 1; \
	done
	$(INSTALL) -d $(DESTDIR)$(MANDIR)
	for DIR in `cd UNIX/man && find . -type d -mindepth 1`; do \
	    $(INSTALL) -d $(DESTDIR)$(MANDIR)/$$DIR; \
	    test $$? || exit 1; \
	done
	for FILE in `cd UNIX/man && find . -type f`; do \
	    gzip -9c UNIX/man/$$FILE > UNIX/man/$$FILE.gz; \
	    test $$? || exit 1; \
	    $(INSTALL) -m644 UNIX/man/$$FILE.gz $(DESTDIR)$(MANDIR)/$$FILE.gz; \
	    test $$? || exit 1; \
	done
	$(INSTALL) -d $(DESTDIR)$(SYSCONFDIR)
	for DIR in `cd UNIX/etc && find . -type d -mindepth 1`; do \
	    $(INSTALL) -d $(DESTDIR)$(SYSCONFDIR)/$$DIR; \
	    test $$? || exit 1; \
	done
	for FILE in `cd UNIX/etc && find . -type f`; do \
	    $(INSTALL) -m644 UNIX/etc/$$FILE $(DESTDIR)$(SYSCONFDIR)/$$FILE; \
	    test $$? || exit 1; \
	done
	$(INSTALL) -d $(DESTDIR)$(DATADIR)/neubot
	for DIR in `find neubot -type d`; do \
	    $(INSTALL) -d $(DESTDIR)$(DATADIR)/$$DIR; \
	    test $$? || exit 1; \
	done
	for FILE in `find neubot -type f`; do \
	    $(INSTALL) -m644 $$FILE $(DESTDIR)$(DATADIR)/$$FILE; \
	    test $$? || exit 1; \
	done
	for PATTERN in 's|@BINDIR@|$(BINDIR)|g' 's|@DATADIR@|$(DATADIR)|g'; do \
	    ./scripts/sed_inplace $$PATTERN \
	        $(DESTDIR)$(BINDIR)/neubot \
	        $(DESTDIR)$(DATADIR)/applications/neubot.desktop \
	        $(DESTDIR)$(DATADIR)/neubot/notifier/unix.py \
	        $(DESTDIR)$(DATADIR)/neubot/viewer/unix.py \
	        $(DESTDIR)$(SYSCONFDIR)/xdg/autostart/neubot.desktop; \
	    test $$? || exit 1; \
	done

# TODO There is more stuff we should uninstall
uninstall:
	@rm -rf $(DESTDIR)$(DATADIR)/neubot
	@rm -rf $(DESTDIR)$(BINDIR)/neubot
	@rm -rf $(DESTDIR)$(BINDIR)/neubotw

#
# Install should be invoked as root and will actually
# copy neubot on the filesystem, making sure that root
# owns the installed files.
#
install:
	@echo "[INSTALL]"
	@make -f Makefile _install INSTALL='install -o 0 -g 0'

#      _      _
#   __| | ___| |__
#  / _` |/ _ \ '_ \
# | (_| |  __/ |_) |
#  \__,_|\___|_.__/
#
# Make package for debian/ubuntu
#

DEB_PACKAGE = dist/$(STEM)-1_all.deb

# Directories to create.
DEB_DATA_DIRS += dist/data/etc/init.d/
DEB_DATA_DIRS += dist/data/etc/apt/sources.list.d/
DEB_DATA_DIRS += dist/data/etc/cron.daily

# Files to copy.
DEB_DATA_FILES += etc/init.d/neubot
DEB_DATA_FILES += etc/apt/sources.list.d/neubot.list
DEB_DATA_FILES += etc/cron.daily/neubot

# Files to `chmod +x`.
DEB_DATA_EXEC += dist/data/etc/init.d/neubot
DEB_DATA_EXEC += dist/data/etc/cron.daily/neubot

_deb_data:
	make -f Makefile _install DESTDIR=dist/data \
	    PREFIX=/usr MANDIR=/usr/share/man
	@for DIR in $(DEB_DATA_DIRS); do \
	 $(INSTALL) -d $$DIR; \
	done
	@for FILE in $(DEB_DATA_FILES); do \
	 $(INSTALL) -m644 debian/$$FILE dist/data/$$FILE; \
	done
	@for FILE in $(DEB_DATA_EXEC); do \
	 chmod 755 $$FILE; \
	done
	@$(INSTALL) -d dist/data/usr/share/doc/neubot
	@$(INSTALL) -m644 debian/copyright dist/data/usr/share/doc/neubot/
	@$(INSTALL) -m644 debian/changelog dist/data/usr/share/doc/neubot/changelog.Debian
	@cd dist/data/usr/share/doc/neubot && gzip -9 changelog.Debian

_deb_data.tgz: _deb_data
	@cd dist/data && tar czf ../data.tar.gz ./*

_deb_control_skel:
	@$(INSTALL) -d dist/control
	@$(INSTALL) -m644 debian/control/control dist/control/control
	@$(INSTALL) -m644 debian/control/conffiles dist/control/conffiles
	@$(INSTALL) debian/control/preinst dist/control/preinst
	@$(INSTALL) debian/control/postinst dist/control/postinst
	@$(INSTALL) debian/control/prerm dist/control/prerm
	@$(INSTALL) debian/control/postrm dist/control/postrm

_deb_control_md5sums:
	@$(INSTALL) -m644 /dev/null dist/control/md5sums
	@./scripts/cksum.py -a md5 `find dist/data -type f` > dist/control/md5sums
	@./scripts/sed_inplace 's|dist\/data\/||g' dist/control/md5sums

_deb_control_size:
	@SIZE=`du -k -s dist/data/|cut -f1` && \
	 ./scripts/sed_inplace "s|@SIZE@|$$SIZE|" dist/control/control

_deb_control:
	@make -f Makefile _deb_control_skel
	@make -f Makefile _deb_control_md5sums
	@make -f Makefile _deb_control_size

_deb_control.tgz: _deb_control
	@cd dist/control && tar czf ../control.tar.gz ./*

_deb_binary:
	@echo '2.0' > dist/debian-binary

#
# Note that we must make _deb_data before _deb_control
# because the latter must calculate the md5sums and the
# total size.
# Fakeroot will guarantee that we don't ship a debian
# package with ordinary user ownership.
# For now we do not fail if lintian fails because there
# is the nonstandard /var/neubot issue pending.
#
_deb:
	@make -f Makefile _deb_data.tgz
	@make -f Makefile _deb_control.tgz
	@make -f Makefile _deb_binary
	@ar r $(DEB_PACKAGE) dist/debian-binary \
	 dist/control.tar.gz dist/data.tar.gz
	@cd dist && rm -rf debian-binary control.tar.gz data.tar.gz \
         control/ data/
	@chmod 644 $(DEB_PACKAGE)

deb:
	@echo "[DEB]"
	@fakeroot make -f Makefile _deb
	@lintian $(DEB_PACKAGE) || true

#           _
#  _ __ ___| | ___  __ _ ___  ___
# | '__/ _ \ |/ _ \/ _` / __|/ _ \
# | | |  __/ |  __/ (_| \__ \  __/
# |_|  \___|_|\___|\__,_|___/\___|
#
# Bless a new neubot release (sources and Debian).
#
release:
	@make clean
	@make deb
	@make archive
	@./scripts/update_apt
	@cd dist && chmod 644 *
