#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./biocolab/ubuntu.sh
else
    bash ./biocolab/rhel.sh
fi