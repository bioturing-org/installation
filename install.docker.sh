#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./docker/ubuntu.sh
else
    bash ./docker/rhel.sh
fi