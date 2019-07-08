# Notes on debugging ICMP No Route messages at the SIX

## Problem

Chris Caputo notified us that our router at the SIX was sending unwanted ICMPv6 No Route replies to packets on the fabric *even though* the packets were not addressed to our machine. More precisely, the machine was receiving ICMPv6 Echo Request packets with destination MAC and IPv6 addresses that were not on the fabric (the sender must have got a MAC address for the IPv6 destination somehow, and the packets were being broadcast by switches and reaching our port); our machine was replying with ICMPv6 No Route (Destination Unreachable) packets.

## Reproducing the issue

The `minimal-test-case.sh` script in this directory deploys the minimum configuration (that I could manage) that reproduces the issue. Removing many of the configuration steps makes the problem disappear (and renders the router non-operational), in particular:

* Removing the `macvlan` from the `ns1/veth-0` makes the problem disappear.
* Removing the `unreachable default` entry in the routing table changes the behavior (assuming IPv6 forwarding is enabled and IPv6 autoconf is disabled). When the route to the destination is the "local" route (auto-generated by assigning an IPv6 address to the interface), the machine (i) replies with NDP Redirect messages *and* (ii) performs neighbor discovery, which then triggers ICMPv6 Address Unreachable messages.

## Notes on kernel investigation

We started debugging checking where the kernel generates NDP Redirects. These are likely triggered inside [`ip6_forward`][ip6_forward_redirect], when the input and output interfaces are the same. Inside [`ndisc_send_redirect`][ndisc_send_redirect], the kernel [apparently][ndisc_send_redirect_ndisc] starts neighbor discovery.

 [ip6_forward_redirect]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/ip6_output.c#L498

 [ndisc_send_redirect]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/ndisc.c#L1563

 [ndisc_send_redirect_ndisc]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/ndisc.c#L1627

After neighbor discovery fails, the kernel generates ICMPv6 Address Unreachable messages. This likely happens in [`ip6_link_failure`][ip6_link_failure], which is (indirectly) called from [`ndisc_error_report`][ndisc_error_report], which is (indirectly) called from [`neigh_invalidate`][neigh_invalidate].

 [ip6_link_failure]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L2239

 [ndisc_error_report]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/ndisc.c#L689

 [neigh_invalidate]: https://github.com/torvalds/linux/blob/v5.0/net/core/neighbour.c#L992

These functions are called when there is no specific route for the destination. If an `unreachable default` route is installed in the routing table (in PEERING's case, routing table 20000 for downstream packets), then the machine sends ICMPv6 No Route packets instead. This is likely because `RTN_UNREACHABLE` routes (indirectly) trigger calls to [`ip6_pkt_discard`][ip6_pkt_discard], apparently the only place where the kernel generates ICMPv6 No Route messages ([see][discard_1] [these][discard_2] [initializations][discard_3]). By following this code, we identified that using `RTN_BLACKHOLE` would likely lead to no packet being generated, as [`dst_discard`][dst_discard] simply drops the packet without generating any response (unlike `ip6_pkt_discard`).

 [ip6_pkt_discard]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L3693

 [discard_1]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L335

 [discard_2]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L309

 [discard_3]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L941

 [dst_discard]: https://github.com/torvalds/linux/blob/v5.0/net/core/dst.c#L46

## Resolution

We have temporarily blocked the ICMPv6 No Route packets at the SIX using an `ip6tables` rule. During our investigation we found that installing a `blackhole default` (instead of `unreachable default`) prevents any ICMPv6 packets from being sent back to the source.

For reference, the `ip6tables` rule temporarily installed at the SIX was:

``` {.sh}
ip6tables -I OUTPUT -p ipv6-icmp --icmpv6-type no-route --out-interface heth1 --destination 2001:504:16::/64 -j DROP
```

## Further investigation

It seems packets arriving on a `macvlan` interface go through the kernel's forwarding logic even if their MAC address does not match the `macvlan`'s MAC address. This does *not* happen with `veth` devices. This behavior seems inconsistent and may be a bug; we plan to investigate it further. We note ICMP No Route and Address Unreachable messages are sent even if the `macvlan` is created with `mode passthru nopromisc`.

We note that `ndisc_send_redirect` also performs FIB lookup (by calling [`ip6_route_output`][ip6_route_output], which then calls [`fib6_rule_lookup`][fib6_rule_lookup]). An alternative explanation for why `macvlan`s and `veth`s behavior differently may be inside the FIB lookup code. However, we note that this is *unlikely*, as disabling IPv6 forwarding gets rid of the NDP Redirect messages but not the ICMPv6 No Route messages (see comment and test case in `minimal-test-case.sh`).

 [ip6_route_output]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/ndisc.c#L1603

 [fib6_rule_lookup]: https://github.com/torvalds/linux/blob/v5.0/net/ipv6/route.c#L2109

## TODO

* Test `blackhole default` @ SIX