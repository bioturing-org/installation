#! /bin/bash

set -e

function to_int {
    local -i num="10#${1}"
    echo "${num}"
}

function port_is_ok {
    local port="$1"
    local -i port_num=$(to_int "${port}" 2>/dev/null)

    if (( $port_num < 1 || $port_num > 65535 )) ; then
        echo "*** ${port} is not a valid port" 1>&2
        return
    fi

    echo 'ok'
}

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_BLUE='\033[0;34m'
_NC='\033[0m' # No Color
_MINIMUM_ROOT_SIZE=64424509440 # 60GB

echo -e "${_BLUE}BioColab UBUNTU installation version${_NC} ${_GREEN}stable${_NC}\n"
echo -e "\n"
# Cert before install other packages in OS
read -p "Install Self-Signed CA Certificate [y, n]: " AGREE_CA
if [ -z "$AGREE_CA" ] || [ "$AGREE_CA" != "y" ]; then
    sudo apt-get install build-essential wget curl ca-certificates -y
else
    sudo apt-get install build-essential wget curl ca-certificates -y
    echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
    sudo bash ./cert/ubuntu.sh
fi

#---------------------------------

# Input Database volume
echo -e "\n"
read -p "Database volume (persistent volume to store Database): " DATABASE_DIR
if [ -z "$DATABASE_DIR" ];
then
    DATABASE_DIR="/ecosystemx/database"
fi
echo -e "DATABASE_DIR=${DATABASE_DIR} \n"
if [ ! -d "$DATABASE_DIR" ];
then
    echo -e "${_RED}Directory [DATABASE_DIR] DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input Application volume
echo -e "\n"
read -p "Application volume (persistent volume to store Application): " APPLICATION_DIR
if [ -z "$APPLICATION_DIR" ];
then
    APPLICATION_DIR="/ecosystemx/application"
fi
echo -e "APPLICATION_DIR=${APPLICATION_DIR} \n"
if [ ! -d "$APPLICATION_DIR" ];
then
    echo -e "${_RED}Directory [APPLICATION_DIR] DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input user data volume
echo -e "\n"
read -p "user_data volume (persistent volume to store user data): " USERDATA_DIR
if [ -z "$USERDATA_DIR" ];
then
    USERDATA_DIR="/ecosystemx/userdata"
fi
echo -e "USERDATA_DIR=${USERDATA_DIR} \n"
if [ ! -d "$USERDATA_DIR" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input example volume
echo -e "\n"
read -p "example volume (share for all members): " EXAMPLE_DIR
if [ -z "$EXAMPLE_DIR" ];
then
    EXAMPLE_DIR="/ecosystemx/examples"
fi
echo -e "EXAMPLE_DIR=${EXAMPLE_DIR} \n"
if [ ! -d "$EXAMPLE_DIR" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi
touch $EXAMPLE_DIR/.debugmode

# Expose ports
echo -e "\n"
read -p "Please input expose HTTP port (80): " HTTP_PORT
if [ -z "$HTTP_PORT" ]; then
    HTTP_PORT=80
fi

HTTP_PORT_VALID=`port_is_ok ${HTTP_PORT}`
if [ "$HTTP_PORT_VALID" == "ok" ]; then
    echo -e "${_BLUE}HTTP port is OK${_NC}\n"
else
    echo -e "${_RED}Invalid expose HTTP port: ${HTTP_PORT}${_NC}\n"
    exit 1
fi

echo -e "\n"
read -p "Please input expose HTTPS port (443): " HTTPS_PORT
if [ -z "$HTTPS_PORT" ]; then
    HTTPS_PORT=443
fi

HTTPS_PORT_VALID=`port_is_ok ${HTTPS_PORT}`
if [ "$HTTPS_PORT_VALID" == "ok" ]; then
    echo -e "${_BLUE}HTTPS port is OK${_NC}\n"
else
    echo -e "${_RED}Invalid expose HTTPS port: ${HTTPS_PORT}${_NC}\n"
    exit 1
fi


#------------
# Docker installation confirmation.
#already_install_count=`ps -ef | grep -i docker | grep -v grep | wc -l`

already_install_count=`pidof dockerd | wc -l`

echo "Docker count : $already_install_count"

if [ $already_install_count -gt 0 ]
then
    echo -e "${_BLUE}Docker is already installed with this server.${_NC}\n"
    docker version
else
# Docker + CUDA
    echo -e "\n"
    echo -e "${_BLUE}Installing docker${_NC}\n"
    curl https://get.docker.com | sh
    sudo systemctl --now enable docker
    sudo systemctl start docker
fi
#------------
#------------
# Check for Nvidia driver and show detail

count_driver=`ls /proc/driver/ | grep -i nvidia | wc -l`

if [ $count_driver -ge 1 ]
then
    echo -e "\nNvidia driver detected."
    nvidia-smi
else
    echo -e "\nNvidia driver is not detecting."
    echo -e "\nIt might be installed later in future."
fi
#------------

# Input GPU
echo -e "\n"
read -p "Do you have GPU on your machine: [y/n]" HAVE_GPU
if [ -z "$HAVE_GPU" ] || [ "$HAVE_GPU" != "y" ];
then
    HAVE_GPU="no"
else
    HAVE_GPU="yes"
    read -p "Do you need install CUDA Toolkit [y, n]: " AGREE_INSTALL
    if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
        echo -e "${_RED}Ignore re-install CUDA Toolkit${_NC}"
    else
        echo -e "${_BLUE}Checking root partition capacity${_NC}"
        ROOT_SIZE=$(df -B1 --output=source,size --total / | grep 'total' | awk '{print $2}')
        if [ "$ROOT_SIZE" -lt "$_MINIMUM_ROOT_SIZE" ];
        then
            echo -e "${_RED}The root partition should be at least 64GB${_NC}"
            exit 1
        fi

        # NVIDIA CUDA Toolkit
        echo -e "${_BLUE}Installing NVIDIA CUDA Toolkit 11.7${_NC}\n"
        wget https://developer.download.nvidia.com/compute/cuda/11.7.1/local_installers/cuda_11.7.1_515.65.01_linux.run
        sudo sh cuda_11.7.1_515.65.01_linux.run
    fi

    read -p "Do you need install NVIDIA Docker 2 [y, n]: " AGREE_INSTALL
    if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
        echo -e "${_RED}Ignore re-install NVIDIA Docker 2${_NC}"
    else
        # NVIDIA CUDA Docker 2
        echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID) &&\
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&\
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        sudo apt-get update
        sudo apt-get install -y nvidia-docker2
        sudo systemctl restart docker
    fi
fi

# Basic package
echo -e "\n"
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo apt-get update
sudo apt install net-tools -y

#Host IP Address
echo "[INFO] Get LAN IP addresses"
ifconfig -a
LIST_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'`
HOST=`echo $LIST_IP | awk -F' ' '{print $NF}'`

echo "Given IP $HOST was detected. Kindly provide ethernet IP. You might have multiple IP's"

echo -e "\n"

read -p "Would you like to change IP[${HOST}] [y, n]: " AGREE_IP_CHANGE
echo -e "\n"

if [ -z "$AGREE_IP_CHANGE" ] || [ "$AGREE_IP_CHANGE" != "y" ]; then
    echo "Host IP will be $HOST"
else
    read -p "Kindly provide IP address: " CLIENT_IP_ADD
    if [ -z "$CLIENT_IP_ADD" ];
    then
        echo -e "${_RED}Empty IP Address... Not allowed.${_NC}"
        exit 1
    else
        HOST="$CLIENT_IP_ADD"
        echo "Host IP will be $HOST"
    fi
fi

if [ -z "$HOST" ]
then
    HOST="0.0.0.0"
fi

# Login to bioturing.com
echo -e "\n"
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
## Image is Public -- Docker login no longer require ##
ECOSYSTEMX_VERSION="3.0.1"
echo -e "${_BLUE}Pulling bioturing ECOSYSTEMX image: ${ECOSYSTEMX_VERSION} ${_NC}"
echo -e "${_BLUE}Logging in to ${_NC}"
ECOSYSTEMX_REPO="bioturing/ecosystemx:3.0.2"
sudo docker pull ${ECOSYSTEMX_REPO}

## stop and remove previous instance
sudo docker stop ecosystemx || true
sudo docker rm ecosystemx || true
sudo docker container stop ecosystemx || true
sudo docker container rm ecosystemx || true

# Pull BioTuring ecosystem
echo -e "${_BLUE}Starting bioturing ECOSYSTEMX image${_NC}"
if [ "$HAVE_GPU" == "y" ] || [ "$HAVE_GPU" == "yes" ]; then
    echo -e "${_BLUE}HAVE_GPU${_NC}\n"
    # NVIDIA Sets the compute mode to Default mode
    echo -e "${_BLUE}NVIDIA Sets the compute mode to Default mode, allowing multiple processes to share the GPU.${_NC}\n"
    nvidia-smi -c 0 || true
        
    sudo docker run -t -i \
        --env-file ./ecosystemx_inside/ecosystemx.env \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v $DATABASE_DIR:/database:rw \
        -v $APPLICATION_DIR:/appdata/share:rw \
        -v $USERDATA_DIR:/home/shared:rw \
        -v $EXAMPLE_DIR:/s3/colab/content:rw \
        --name ecosystemx \
        --gpus all \
        --cap-add SYS_ADMIN \
        --device /dev/fuse \
        --security-opt apparmor:unconfined \
        -d --privileged --restart always ${ECOSYSTEMX_REPO}
else
    echo -e "${_RED}NO_GPU${_NC}\n"
    sudo docker run -t -i \
        --env-file ./ecosystemx_inside/ecosystemx.env \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v $DATABASE_DIR:/database:rw \
        -v $APPLICATION_DIR:/appdata/share:rw \
        -v $USERDATA_DIR:/home/shared:rw \
        -v $EXAMPLE_DIR:/s3/colab/content:rw \
        --name ecosystemx \
        --cap-add SYS_ADMIN \
        --device /dev/fuse \
        --security-opt apparmor:unconfined \
        -d --privileged --restart always ${ECOSYSTEMX_REPO}
fi
