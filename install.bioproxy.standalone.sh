#!/bin/bash

set -e

# Check Physical Memory
#----------------------
echo "Checking physical memory..."
  PHYSICAL_MEMORY=$(free -m | grep Mem | awk '{print $2}')

  # Convert to GB for comparison (since free -m returns memory in MB)
  PHYSICAL_MEMORY_GB=$((PHYSICAL_MEMORY / 1024))

  echo "Physical Memory : ${PHYSICAL_MEMORY_GB}GB"

  # Check if physical memory is at least 60GB
  if [ "$PHYSICAL_MEMORY_GB" -lt 60 ]; then
    echo "Error: Insufficient physical memory. At least 60GB of RAM is required."
    exit 1  # Exit the script if memory is less than 60GB
  fi

# Check Swap
#-----------
bash ./check_swap/check_swap.sh

if [ -f /etc/lsb-release ]; then
    bash ./bioproxy/ubuntu.sh
else
    bash ./bioproxy/rhel.sh
fi