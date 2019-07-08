#!/bin/sh
set -u

ip link delete br0 > /dev/null 2>&1
ip netns delete ns0 > /dev/null 2>&1
ip link del vebr0 > /dev/null 2>&1
ip link del vebr1 > /dev/null 2>&1
