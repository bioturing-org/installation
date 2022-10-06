#! /bin/bash

set -e

_RED='\033[0;31m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color

read -p "Do you need install CUDA Toolkit [y, n]: " AGREE_INSTALL
if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
    echo -e "${_RED}Ignore re-install CUDA Toolkit${_NC}"
else
    if [ -f /etc/lsb-release ]; then
        # NVIDIA CUDA Toolkit
        echo -e "${_BLUE}Installing NVIDIA CUDA Toolkit 11.7${_NC}\n"
        wget https://developer.download.nvidia.com/compute/cuda/11.7.1/local_installers/cuda_11.7.1_515.65.01_linux.run
        sudo sh cuda_11.7.1_515.65.01_linux.run

        # NVIDIA CUDA Docker 2
        echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID) &&\
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&\
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        sudo apt-get update
        sudo apt-get install -y nvidia-docker2
    else
        # NVIDIA CUDA Toolkit
        echo -e "${_BLUE}Installing NVIDIA CUDA Toolkit 11.7${_NC}\n"
        wget https://developer.download.nvidia.com/compute/cuda/11.7.1/local_installers/cuda_11.7.1_515.65.01_linux.run
        sudo sh cuda_11.7.1_515.65.01_linux.run

        # NVIDIA CUDA Docker 2
        echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
        && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
        sudo yum clean expire-cache
        sudo yum install -y nvidia-docker2
    fi

    read -s -p "K8s Container engine is Docker [y, n]: " AGREE_ENGINE
    if [ -z "$AGREE_ENGINE" ] || [ "$AGREE_ENGINE" != "y" ]; then
        sudo systemctl restart docker
    else
    sudo systemctl restart containerd
    fi

    nvidiadata=`nvidia-smi --query-gpu=name --format=csv,noheader`
    IFS='. ' read -r -a arr_data <<< "${nvidiadata}"

    echo -e "${_BLUE}Need enable nvidia-fabricmanager [for the A100 only]${_NC}\n"
    nvidia_special="A100"
    if [ "${arr_data[1],,}" = "${nvidia_special,,}" ]; then
        nvidiainfo=`modinfo -F version nvidia`
        IFS='. ' read -r -a arr_info <<< "${nvdiainfo}"
        if [ -f /etc/lsb-release ]; then
            sudo apt-get install cuda-drivers-fabricmanager-${arr_info[0]}
            sudo systemctl --now enable nvidia-fabricmanager
        else
            sudo yum install cuda-drivers-fabricmanager-${arr_info[0]}
            sudo systemctl enable nvidia-fabricmanager
            sudo systemctl restart nvidia-fabricmanager
        fi
    fi
fi
