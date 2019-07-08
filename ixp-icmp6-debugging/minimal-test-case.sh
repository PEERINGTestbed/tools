#!/bin/bash
set -eu
set -x

create_namespace () {
    local nsname=$1
    if [[ -e /var/run/netns/$nsname ]] ; then
        ip netns delete $nsname
    fi
    ip netns add $nsname
}

create_bridge () {
    local brname=$1
    if ip link show dev $brname &> /dev/null ; then
        ip link del dev $brname
    fi
    ip link add dev $brname type bridge
    ip link set dev $brname up
}

create_setup_veth () {
    local brname=$1
    local nsname=$2
    local brveth=$3
    local veth=$4
    local addr6=$5
    if ip link show dev $veth &> /dev/null ; then
        ip link del dev $veth
    fi
    if ip link show dev $brveth &> /dev/null ; then
        ip link del dev $brveth
    fi
    echo "setting up $brveth and $veth @ $nsname [$addr6]"
    ip link add dev $veth type veth peer name $brveth
    ip link set dev $brveth master $brname
    ip link set dev $brveth up
    ip link set dev $veth netns $nsname
    ip netns exec $nsname ip -6 addr add $addr6 dev $veth
    ip netns exec $nsname ip link set dev $veth up
}

create_bridge br0
create_namespace ns0
create_namespace ns1
create_setup_veth br0 ns0 vebr0 veth 4000:10::10:1/64
create_setup_veth br0 ns1 vebr1 veth 4000:10::11:1/64

# Hardcode a MAC address for the out-of-fabric 4000:10::4000:1 address:
ip netns exec ns0 ip neigh add 4000:10::4000:1 lladdr 00:11:22:33:44:55 dev veth

# We use a specific routing table to avoid the routes for 4000::10/64 in the
# default table. Commenting these out solves the problem, but if IPv6 forwarding
# is enabled and IPv6 autoconf is disabled (likely the case for routers), then
# the machine replies with ICMP Address Unreachable instead. You can test this
# case by uncommenting the execution of sysctl. Changing the route to `blackhole
# default` solves the problem (regardless of IPv6 forwarding and autoconf).
ip netns exec ns1 ip -6 rule add iif macv lookup 100
ip netns exec ns1 ip -6 route add unreachable default proto static table 100
# ip netns exec ns1 sysctl -q -p sysctl.conf

# Configure macvlan device (commenting these out solves the problem):
ip netns exec ns1 ip link add link veth macv type macvlan mode passthru nopromisc
ip netns exec ns1 ip link set dev macv up
ip netns exec ns1 ip addr add 4000:10::11:1/64 dev macv

exit 0