#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./ecosystemx_inside/ubuntu.sh
else
    bash ./ecosystemx_inside/rhel.sh
fi