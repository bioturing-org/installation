# Issue  : Kernel update - after reboot cuda needs to be reinstall.
# Author : BioTuring

# Make the script executable
# chmod +x install_cuda_reboot.sh

# Put below entry on cron
# 
# @reboot /nvidia-driver/install_cuda_reboot.sh > /nvidia-driver/cuda_install_reboot.log 2>&1

# Delay 15 min. these commands slightly to ensure the driver is loaded

# @reboot sleep 900 && nvidia-smi -pm 1
# @reboot sleep 900 && nvidia-smi -c 0


#!/bin/bash
set -x

# Path to your CUDA .run file
# CUDA_RUN_FILE="/nvidia-driver/cuda_12.5.0_555.42.02_linux.run"

CUDA_RUN_FILE="/<path of cuda run file >/<cuda run file>"

# Check if nvidia-smi command is available
if ! command -v nvidia-smi &> /dev/null; then
    echo "CUDA is not installed. Installing now..."

    # Install the CUDA driver silently
    sudo sh "$CUDA_RUN_FILE" --silent --toolkit --driver --no-drm < /dev/null || true

    # Verify installation
    if command -v nvidia-smi &> /dev/null; then
        echo "CUDA successfully installed."
    else
        echo "CUDA installation failed."
    fi
else
    echo "CUDA is already installed."
    nvidia-smi
fi
