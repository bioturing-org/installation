#!/bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./ecosystemx_inside/ubuntu.sh
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "centos" ]]; then
        bash ./ecosystemx_inside/centos.sh
    else
        bash ./ecosystemx_inside/rhel.sh
    fi
fi
