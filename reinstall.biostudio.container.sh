#! /bin/bash

set -e

if [ -f /etc/lsb-release ]; then
    bash ./biostdio_restart_container/ubuntu.sh
else
    bash ./biostdio_restart_container/rhel.sh
fi
 
