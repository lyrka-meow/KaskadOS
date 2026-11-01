#!/usr/bin/bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# All ip/nft/sysctl writes happen inside a fresh user + network namespace.
# The unprivileged parent never calls a privileged hotspot action.
exec /usr/bin/unshare --user --map-root-user --net /usr/bin/bash -Eeuo pipefail -c '
    source <(/usr/bin/sed '\''/^case "${action}" in/,$d'\'' "$1/kaskados-hotspot-control")
    /usr/bin/ip link add kaskad-ap type dummy
    /usr/bin/ip addr add 10.42.0.1/24 dev kaskad-ap
    /usr/bin/ip link set kaskad-ap up
    /usr/bin/nft add table inet unrelated_test
    ensure_repeater_routing
    /usr/bin/nft delete table ip kaskados_repeater_nat
    /usr/bin/sysctl -q -w net.ipv4.ip_forward=0
    ensure_repeater_routing
    /usr/bin/nft list table ip kaskados_repeater_nat | /usr/bin/grep -q kaskados-hotspot-nat-v1
    /usr/bin/nft list table inet kaskados_repeater_filter | /usr/bin/grep -q kaskados-hotspot-return-v1
    /usr/bin/nft list table inet unrelated_test >/dev/null
    [[ "$(< /proc/sys/net/ipv4/ip_forward)" == 1 ]]
    /usr/bin/ip link add enp-test type dummy
    /usr/bin/ip link set enp-test up
    /usr/bin/ip link add regalia0 type dummy
    /usr/bin/ip link set regalia0 up
    /usr/bin/ip rule add priority 9001 fwmark 0x2023 table 2022
    /usr/bin/ip route add default dev regalia0 table 2022
    ensure_ethernet_vpn_routing enp-test true
    /usr/bin/nft list table inet kaskados_ethernet_vpn | /usr/bin/grep -q kaskados-ethernet-vpn-mark-v1
    /usr/bin/nft list table inet kaskados_ethernet_vpn | /usr/bin/grep -q kaskados-ethernet-vpn-killswitch-v1
    /usr/bin/ip -4 route get 1.1.1.1 mark 0x2023 | /usr/bin/grep -q "dev regalia0"
    /usr/bin/nft list table inet unrelated_test >/dev/null
    printf "%s\n" "Isolated nft recreation and forwarding recovery passed; unrelated table preserved."
' hotspot-routing-test "${test_dir}"
