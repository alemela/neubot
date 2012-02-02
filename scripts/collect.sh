#!/bin/sh

#
# Copyright (c) 2012 Simone Basso <bassosimone@gmail.com>,
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
# Helper script to collect Neubot results from remote servers
# and to publish it on some HTTP or FTP location.
# Optionally anonymize results that do not contain the permission
# to publish.  This should not happen for newer clients but may
# be the case with before 0.4.6 clients.
#

#
# Periodically invoke this command to fetch new results from
# neubot servers and copy them on your local machine.
# Ideally, this script should be in cron(1) and should run
# everyday and sync the local results copy.
# This is just a convenience wrapper around rsync and it sets
# the maximum bandwidth to a reasonable value to avoid hogging
# resources on the measurement server.
#
pull()
{
    localdir="master.neubot.org"
    remote="master.neubot.org:/var/lib/neubot/*"

    options=$(getopt d:nR:v $*)
    if [ $? -ne 0 ]; then
        echo "Usage: pull [-nv] [-d localdir] [-R remote]" 2>&1
        echo "Default remote: $remote" 2>&1
        echo "Default localdir: $localdir" 2>&1
        exit 1
    fi

    set -- $options

    # Do not tollerate errors
    set -e

    while [ $# -ge 0 ]; do
        if [ "$1" = "-d" ]; then
            localdir=$2
            shift
            shift
        elif [ "$1" = "-n" ]; then
            flags="$flags -n"
            shift
        elif [ "$1" = "-R" ]; then
            remote=$2
            shift
            shift
        elif [ "$1" = "-v" ]; then
            flags="$flags -v"
            shift
        elif [ "$1" = "--" ]; then
            shift
            break
        fi
    done

    rsync -rt --bwlimit=512 $flags $remote $localdir
}

#
# This is just a convenience command that is invoked to
# inspect the content of a result and tell whether we
# can publish it directly or it needs some postprocessing.
# This should not happen for new versions of Neubot but
# there is a shrinking number of old clients around.
# Here we use Python because it is a pain to inspect the
# content from the command line.
#
privacy_ok()
{
    python - $* << EOF
import json
import sys
import gzip

filep = gzip.open(sys.argv[1], 'rb')
content = filep.read()
dictionary = json.loads(content)
if (int(dictionary.get('privacy_informed', 0)) == 1 and
    int(dictionary.get('privacy_can_collect', 0)) == 1 and
    int(dictionary.get('privacy_can_publish', 0)) == 1):

    # Privacy is OK
    sys.exit(0)

sys.exit(1)
EOF
}

#
# This is a simple postprocessing step that moves the
# results that have the permission to publish into a
# subdirectory and results that have not the permission
# into another subdirectory.
# This command is idempotent and does not process the
# same directory twice.
#
classify_by_privacy()
{
    log_always=echo
    log_info=:

    options=$(getopt v $*)
    if [ $? -ne 0 ]; then
        echo "Usage: classify_by_privacy [-v]" 2>&1
        exit 1
    fi

    set -- $options

    # Do not tollerate errors
    set -e

    while [ $# -ge 0 ]; do
        if [ "$1" = "-v" ]; then
            log_info=echo
            shift
        elif [ "$1" = "--" ]; then
            shift
            break
        fi
    done

    for rawdir in $*; do

        if [ -d $rawdir/pubdir ]; then
            $log_info "$0: already classified: $rawdir"
            continue
        fi

        ok_count=0
        bad_count=0

        mkdir $rawdir/pubdir $rawdir/privdir
        for file in $rawdir/*.gz; do
            if privacy_ok $file; then
                $log_info "$0: privacy ok: $file"
                ok_count=$(($ok_count + 1))
                destdir=$rawdir/pubdir
            else
                $log_info "$0: bad privacy: $file"
                bad_count=$(($bad_count + 1))
                destdir=$rawdir/privdir
            fi
            cp $file $destdir
        done

        $log_always "$rawdir: ok_count: $ok_count, bad_count: $bad_count"
    done
}

#
# Here's another simple postprocessing step: compress all the
# publisheable files into a tarball and commit it into the git
# repository used for the purpose.
# Automatically separate publisheable and nonpublisheable data
# if that's needed.
#
prepare_for_publish()
{
    log_info=:
    log_error=echo
    noisy=''

    options=$(getopt v $*)
    if [ $? -ne 0 ]; then
        echo "Usage: prepare_for_publish [-v]" 2>&1
        exit 1
    fi

    # Do not tollerate errors
    set -e

    set -- $options

    while [ $# -ge 0 ]; do
        if [ "$1" = "-v" ]; then
            log_info=echo
            noisy='-v'
            shift
        elif [ "$1" = "--" ]; then
            shift
            break
        fi
    done

    for rawdir in $*; do

        #
        # Make sure we don't prepare $today for publish because the
        # data collection is not complete for that directory.
        #
        if ls $rawdir|head -n1|grep -q $(date +^%Y%m%d); then
            $log_info "$0: skipping today"
            continue
        fi

        if [ ! -d $rawdir/pubdir ]; then
            classify_by_privacy $noisy $rawdir
        fi

        # Parametrize the tarball name so we can change it easily
        tarball=results.tar
        if [ -f $rawdir/$tarball.gz ]; then
            $log_info "$0: already prepared: $rawdir"
            continue
        fi

        # Separate gunzip and tar -rf to ease testing
        for file in $(ls $rawdir/pubdir/*.gz); do
            $log_info "$0: gunzip $file"
            gunzip $file
        done
        for file in $(ls $rawdir/pubdir/*); do
            $log_info "$0: tar -rf $(basename $file)"
            tar -C $rawdir/pubdir -rf $rawdir/$tarball $(basename $file)
        done

        $log_info "gzip -9 $rawdir/$tarball"
        gzip -9 $rawdir/$tarball
        (
        cd $rawdir && git add $tarball.gz && \
          git commit -m "Add $rawdir" $tarball.gz
        )

        #
        # Empty line to separate per-directory logs in the
        # report mailed by cron.
        #
        $log_info ""
    done
}

#
# Find all the results.tar.gz files below a given directory
# and publish them at a remote location.
# This is the last step of the deployment pipeline and it runs
# after the postprocessing phase.
#
publish()
{
    remote=server-nexa.polito.it:releases/data/
    noisy=''

    options=$(getopt R:v $*)
    if [ $? -ne 0 ]; then
        echo "Usage: publish [-v] [-R remote] localdir..." 2>&1
        exit 1
    fi

    # Do not tollerate errors
    set -e

    set -- $options

    while [ $# -ge 0 ]; do
        if [ "$1" = "-R" ]; then
            remote=$2
            shift
            shift
        elif [ "$1" = "-v" ]; then
            noisy='-v'
            shift
        elif [ "$1" = "--" ]; then
            shift
            break
        fi
    done

    for rawdir in $*; do
        (
        cd $rawdir && \
          rsync -aR $noisy \
            $(find -type f -name results.tar.gz) $remote
        )
    done
}

usage="Usage: collect.sh pull|prepare|publish [options] [arguments]"

if [ $# -eq 0 ]; then
    echo $usage
    exit 0
elif [ "$1" = "pull" ]; then
    shift
    pull $*
elif [ "$1" = "prepare" ]; then
    shift
    prepare_for_publish $*
elif [ "$1" = "publish" ]; then
    shift
    publish $*
else
    echo "Unknown command: $1"
    echo $usage
    exit 1
fi