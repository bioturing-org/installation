#!/bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./bioturing_ecosystem/ubuntu.sh
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "centos" ]]; then
        bash ./bioturing_ecosystem/centos.sh
    else
        bash ./bioturing_ecosystem/rhel.sh
    fi
fi
