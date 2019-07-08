#!/bin/bash
set -eu
set -x

MACVLANS=simple

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
create_bridge br1
create_namespace ns0
create_namespace ns1
create_namespace ns2
create_setup_veth br0 ns0 vebr-0-0 veth 4000:10::10:1/64
create_setup_veth br0 ns1 vebr-0-1 veth-0 4000:10::11:1/64
create_setup_veth br1 ns1 vebr-1-1 veth-1 4000:11::11:1/64
create_setup_veth br1 ns2 vebr-1-2 veth 4000:11::12:1/64

ip netns exec ns0 ip neigh add 4000:10::4000:1 lladdr 00:11:22:33:44:55 dev veth

ip netns exec ns1 sysctl -q -p sysctl.conf

if [[ "$MACVLANS" == nested ]] ; then
    ip netns exec ns1 ip addr del 4000:10::11:1/64 dev veth-0
    ip netns exec ns1 ip addr del 4000:11::11:1/64 dev veth-1
    create_namespace ns1c
    ip netns exec ns1c sysctl -q -p sysctl.conf
    ip netns exec ns1 ip link add link veth-0 macv-0 type macvlan mode passthru
    ip netns exec ns1 ip link add link veth-1 macv-1 type macvlan mode passthru
    ip netns exec ns1 ip link set dev macv-0 netns ns1c
    ip netns exec ns1 ip link set dev macv-1 netns ns1c
    ip netns exec ns1c ip link set dev macv-0 up
    ip netns exec ns1c ip link set dev macv-1 up
    ip netns exec ns1c ip addr add 4000:10::11:1/64 dev macv-0
    ip netns exec ns1c ip addr add 4000:11::11:1/64 dev macv-1
    ip netns exec ns1c ip -6 rule add iif macv-0 lookup 100
    ip netns exec ns1c ip -6 rule add iif macv-1 lookup 100
    ip netns exec ns1c \
            ip -6 route add unreachable default proto static table 100
elif [[ "$MACVLANS" == simple ]] ; then
    ip netns exec ns1 ip addr del 4000:10::11:1/64 dev veth-0
    ip netns exec ns1 ip link add link veth-0 macv-0 type macvlan mode passthru nopromisc
    ip netns exec ns1 ip link set dev macv-0 up
    ip netns exec ns1 ip addr add 4000:10::11:1/64 dev macv-0
    ip netns exec ns1 ip -6 rule add iif macv-0 lookup 100
    ip netns exec ns1 ip -6 route add unreachable default proto static table 100
elif [[ "$MACVLANS" == none ]] ; then
    ip netns exec ns1 ip -6 rule add iif veth-0 lookup 100
    ip netns exec ns1 ip -6 route add unreachable default proto static table 100
fi

    # ip netns exec ns1 ip rule add iif macv-0 lookup 100
# else
    # ip netns exec ns1 ip rule add iif veth-0 lookup 100

exit 0
