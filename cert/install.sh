#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./ubuntu.sh
else
    bash ./rhel.sh
fi