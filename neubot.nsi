# neubot.nsi

#
# Copyright (c) 2010 Simone Basso <bassosimone@gmail.com>,
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
# Use NSIS to create neubot installer
#

name "neubot 0.3.4"
outfile "neubot-0.3.4-setup.exe"
installdir "$PROGRAMFILES\neubot"
setcompressor lzma
section
    #
    # If a previous version is already installed uninstall it. We need
    # to pass uninstall.exe the magic argument below otherwise execwait
    # will not wait for the uninstaller (see NSIS wiki).
    # To be sure that the system is not locking anymore uninstall.exe
    # so that we can overwrite it, we sleep for a while.
    #
    iffileexists "$INSTDIR\uninstall.exe" 0 +3
        execwait '"$INSTDIR\uninstall.exe" _?=$INSTDIR'
        sleep 2000
    setoutpath "$INSTDIR"
    file /r "dist\*.*"
    writeuninstaller "$INSTDIR\uninstall.exe"
    createdirectory "$SMPROGRAMS\neubot"
    createshortcut "$SMPROGRAMS\neubot\neubot (gui).lnk"		\
      "$INSTDIR\neubotw.exe"
    createshortcut "$SMPROGRAMS\neubot\neubot (start).lnk"		\
      "$INSTDIR\neubotw.exe" "start"
    createshortcut "$SMPROGRAMS\neubot\neubot (stop).lnk"		\
      "$INSTDIR\neubotw.exe" "stop"
    createshortcut "$SMPROGRAMS\neubot\uninstall.lnk" "$INSTDIR\uninstall.exe"
    createshortcut "$SMSTARTUP\neubot (autostart).lnk"			\
      "$INSTDIR\neubotw.exe" "start"
    WriteRegStr HKLM                                                    \
      "Software\Microsoft\Windows\CurrentVersion\Uninstall\neubot"      \
      "DisplayName" "neubot 0.3.4"
    WriteRegStr HKLM                                                    \
      "Software\Microsoft\Windows\CurrentVersion\Uninstall\neubot"      \
      "UninstallString" "$INSTDIR\uninstall.exe"
    exec '"$INSTDIR\neubotw.exe" start'
sectionend
section "uninstall"
    #
    # To be sure that the system is not locking anymore neubotw.exe
    # so that we can remove it, we sleep for a while.
    #
    execwait '"$INSTDIR\neubotw.exe" stop'
    sleep 2000
    rmdir /r "$INSTDIR"
    rmdir /r "$SMPROGRAMS\neubot"
    delete "$SMSTARTUP\neubot (autostart).lnk"
    deleteregkey HKLM                                                   \
      "Software\Microsoft\Windows\CurrentVersion\Uninstall\neubot"
sectionend
