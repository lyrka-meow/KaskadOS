#!/usr/bin/bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Load only pure definitions. Never enter the privileged action dispatcher.
source <(/usr/bin/sed '/^case "${action}" in/,$d' "${test_dir}/kaskados-hotspot-control")

for candidate in 10.42.0.1/24 10.42.0.128/25 10.42.0.7 10.42.0.0/16 10.0.0.0/8; do
    hotspot_subnet_overlaps "${candidate}" || { echo "missed conflict: ${candidate}" >&2; exit 1; }
done
for candidate in 10.42.1.1/24 192.168.0.1/24 0.0.0.0/0 default invalid; do
    if hotspot_subnet_overlaps "${candidate}"; then
        echo "false conflict: ${candidate}" >&2
        exit 1
    fi
done

test_addresses='2: wlan0 inet 192.168.0.104/24 brd 192.168.0.255 scope global wlan0
5: kaskad-ap inet 10.42.0.1/24 brd 10.42.0.255 scope global kaskad-ap'
test_routes='default via 192.168.0.1 dev wlan0
10.42.0.0/24 dev kaskad-ap proto kernel scope link src 10.42.0.1'
function /usr/bin/ip() {
    if [[ "$*" == '-o -4 addr show' ]]; then
        printf '%s\n' "${test_addresses}"
    elif [[ "$*" == '-4 route show table main' ]]; then
        printf '%s\n' "${test_routes}"
    else
        echo "unexpected ip invocation: $*" >&2
        return 1
    fi
}
check_hotspot_subnet
test_addresses+=$'\n3: enp0s31f6 inet 10.42.0.1/24 scope global enp0s31f6'
if check_hotspot_subnet 2>/dev/null; then
    echo 'duplicate Ethernet/AP address not detected' >&2
    exit 1
fi
test_addresses='2: wlan0 inet 192.168.0.104/24 scope global wlan0'
test_routes+=$'\n10.42.0.128/25 via 192.168.0.1 dev wlan0'
if check_hotspot_subnet 2>/dev/null; then
    echo 'overlapping route not detected' >&2
    exit 1
fi

test_existing_rules=false
test_nft_failure=false
test_transactions=0
test_rules=''
function /usr/bin/nft() {
    case "$*" in
        'list table ip kaskados_repeater_nat')
            "${test_existing_rules}" || return 1
            printf '%s\n' 'comment "kaskados-hotspot-nat-v1"'
            ;;
        'list table inet kaskados_repeater_filter')
            "${test_existing_rules}" || return 1
            printf '%s\n' 'comment "kaskados-hotspot-out-v1"' 'comment "kaskados-hotspot-return-v1"'
            ;;
        '-f -')
            test_transactions=$((test_transactions + 1))
            IFS= read -r -d '' test_rules || true
            ! "${test_nft_failure}"
            ;;
        *)
            echo "unexpected nft invocation: $*" >&2
            return 1
            ;;
    esac
}
function /usr/bin/sysctl() {
    [[ "$*" == '-q -w net.ipv4.ip_forward=1' ]]
}
ensure_repeater_routing
[[ "${test_transactions}" -eq 1 ]]
[[ "${test_rules}" == *'destroy table ip kaskados_repeater_nat'* ]]
[[ "${test_rules}" == *'destroy table inet kaskados_repeater_filter'* ]]
[[ "${test_rules}" == *'iifname "kaskad-ap" ip saddr 10.42.0.0/24'* ]]
[[ "${test_rules}" != *'flush ruleset'* && "${test_rules}" != *'regalia'* ]]
test_existing_rules=true
ensure_repeater_routing
[[ "${test_transactions}" -eq 1 ]] # Healthy state is not rewritten.
test_existing_rules=false
test_nft_failure=true
if ensure_repeater_routing; then
    echo 'failed nft transaction reported success' >&2
    exit 1
fi
printf '%s\n' 'Hotspot subnet and atomic routing tests passed (mock commands only).'
