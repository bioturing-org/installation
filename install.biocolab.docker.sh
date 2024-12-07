#!/bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./biocolab/ubuntu.sh
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "centos" ]]; then
        bash ./biocolab/centos.sh
    else
        bash ./biocolab/rhel.sh
    fi
fi
