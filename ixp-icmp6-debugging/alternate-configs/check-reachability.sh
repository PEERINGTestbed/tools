#!/bin/bash
set -u

ip netns exec ns0 ping6 -c 1 4000:10::11:1
ip netns exec ns1 ping6 -c 1 4000:10::10:1

ip netns exec ns1 ping6 -c 1 4000:11::12:1
ip netns exec ns2 ping6 -c 1 4000:11::11:1

# ip netns exec ns0 ping6 -c 1 4000:11::12:1
# ip netns exec ns2 ping6 -c 1 4000:10::10:1

urxvt -e ip netns exec ns1 tcpdump -e -x -i veth-0 &
ip netns exec ns0 ping6 -c 5 4000:10::4000:1