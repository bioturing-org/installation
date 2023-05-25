#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./bioproxy/ubuntu.sh
else
    bash ./bioproxy/rhel.sh
fi