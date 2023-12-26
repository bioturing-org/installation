#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./bioturing_ecosystem/ubuntu.sh
else
    bash ./bioturing_ecosystem/rhel.sh
fi