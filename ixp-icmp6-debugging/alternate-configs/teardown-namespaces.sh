#!/bin/sh
set -u

for bri in 0 1 ; do
    ip link delete br-$bri > /dev/null 2>&1
    for nsi in 0 1 2 ; do
        ip netns delete ns-$nsi > /dev/null 2>&1
        ip link del vebr-$bri-$nsi > /dev/null 2>&1
    done
done
