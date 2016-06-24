#!/bin/bash

lockfile=/var/lock/checkIntruders

if ( set -o noclobber; echo "$$" > "$lockfile") 2> /dev/null; then

	trap 'rm -f "$lockfile"; exit $?' INT TERM EXIT

	# do stuff here

/usr/local/sbin/checkIntruders.pl

        # clean up after yourself, and release your trap
        rm -f "$lockfile"
        trap - INT TERM EXIT
else
        echo " Lock Exists: $lockfile owned by $(cat $lockfile) "
fi
