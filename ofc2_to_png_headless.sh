#!/bin/sh
# Runs the OFC2 to PNG conversion tool, with
# the given command-line arguments, inside a
# virtual (dummy) X server session.
#--
# Copyright protects this work.
# See LICENSE file for details.
#++

export DISPLAY=:9
Xvfb $DISPLAY &
server=$!

$(dirname "$0")/ofc2_to_png.rb "$@"
status=$?

kill $server
exit $status
