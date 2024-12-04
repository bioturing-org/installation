#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./ecosystem_standalone_inside/ubuntu.sh
else
    bash ./ecosystem_standalone_inside/rhel.sh
fi