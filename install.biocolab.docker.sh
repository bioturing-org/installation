#!/bin/bash

set -e

# Check Physical Memory
#----------------------
echo "Checking physical memory..."
  PHYSICAL_MEMORY=$(free -m | grep Mem | awk '{print $2}')

  # Convert to GB for comparison (since free -m returns memory in MB)
  PHYSICAL_MEMORY_GB=$((PHYSICAL_MEMORY / 1024))

  echo "Physical Memory : ${PHYSICAL_MEMORY_GB}GB"

  # Check if physical memory is at least 64GB
  if [ "$PHYSICAL_MEMORY_GB" -lt 64 ]; then
    echo "Error: Insufficient physical memory. At least 64GB of RAM is required."
    exit 1  # Exit the script if memory is less than 64GB
  fi

# Check Swap
#-----------
bash ./check_swap/check_swap.sh

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
