#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=network
module_version=1
module_description='Network diagnostics, packet capture, throughput testing, and security auditing tools'
module_max_size=$((32 * 1024 * 1024))
module_relocate_usr=true
module_components=(
    jansson
    libpcap
    mtr
    traceroute
    tcpdump
    iperf3
    nmap
)

module_main "$@"
"$MODULE_DIR/test.sh"
