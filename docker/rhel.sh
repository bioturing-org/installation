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

echo -e "${_BLUE}BioTuring ecosystem RHEL installation version${_NC} ${_GREEN}stable${_NC}\n"

# Input BioTuring Token
read -p "BioTuring token (please contact support@bioturing.com for a token): " BIOTURING_TOKEN
if [ -z "$BIOTURING_TOKEN" ];
then
    echo -e "${_RED}Empty token is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input user data volume
read -p "user_data volume (persistent volume to store user data): " USER_DATA_VOLUME
if [ ! -d "$USER_DATA_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input app data volume
read -p "app_data volume (this is the place to store the binary files of all services): " APP_DATA_VOLUME
if [ ! -d "$APP_DATA_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input SSL volume
read -p "ssl volume (this directory must contain two files: tls.crt and tls.key from your SSL certificate for HTTPS): " SSL_VOLUME
if [ ! -d "$SSL_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input domain name
read -p "Domain name (example: bioturing.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ];
then
    echo -e "${_RED}Empty domain name is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input administrator username
read -p "Administrator username (example: admin): " ADMIN_USERNAME
if [ -z "$ADMIN_USERNAME" ];
then
    echo -e "${_RED}Empty administrator username is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input administrator password
read -s -p "Administrator password: " ADMIN_PASSWORD
if [ -z "$ADMIN_PASSWORD" ];
then
    echo -e "${_RED}Empty administrator password is not allowed. Exiting...${_NC}"
    exit 1
fi

# Confirm administrator password
read -s -p "Confirm administrator password: " ADMIN_PASSWORD_CONFIRM
if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ];
then
    echo -e "${_RED}Password does not match. Exiting...${_NC}"
    exit 1
fi

# Basic package
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo yum update -y
sudo yum groupinstall 'Development Tools'

# Cert
read -p "Install Self-Signed CA Certificate [y, n]: " AGREE_CA
if [ -z "$AGREE_CA" ] || [ "$AGREE_CA" != "y" ]; then
    sudo yum install curl wget ca-certificates -y
else
    sudo yum install curl wget ca-certificates -y
    echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
    sudo bash ./cert/rhel.sh
fi

# Expose ports
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

# Docker
echo -e "${_BLUE}Installing docker${_NC}\n"
RHEL_VERSION=$(uname -r | sed 's/^.*\(el[0-9]\+\).*$/\1/')
if [ "$RHEL_VERSION" == "el7" ]; fi
then
    sudo cat >> /etc/yum.repos.d/docker-ce.repo << EOF
        [centos-extras]
        name=Centos extras - $basearch
        baseurl=http://mirror.centos.org/centos/7/extras/x86_64
        enabled=1
        gpgcheck=1
        gpgkey=http://centos.org/keys/RPM-GPG-KEY-CentOS-7
EOF
    sudo yum install -y slirp4netns fuse-overlayfs container-selinux
fi
sudo yum install -y yum-utils
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

HAVE_GPU="no"
read -p "Do you need to install CUDA Toolkit [y, n]: " AGREE_INSTALL
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
    HAVE_GPU="yes"
fi

read -p "Do you need to install NVIDIA Docker 2 [y, n]: " AGREE_INSTALL
if [ -z "$AGREE_INSTALL" ] || [ "$AGREE_INSTALL" != "y" ]; then
    echo -e "${_RED}Ignore re-install NVIDIA Docker 2${_NC}"
else
    # NVIDIA CUDA Docker 2
    echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
    && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    sudo yum clean expire-cache
    sudo yum install -y nvidia-docker2
    sudo systemctl restart docker
    HAVE_GPU="yes"
fi

# Check Version
read -p "Please enter BBrowserX's VERSION (latest): " BBVERSION
if [ -z "$BBVERSION" ]; then
    BBVERSION="latest"
fi

# Log in to registry.bioturing.com
echo -e "${_BLUE}Logging in to registry.bioturing.com${_NC}"
sudo docker login registry.bioturing.com

# Pull BioTuring ecosystem
echo -e "${_BLUE}Pulling bioturing ecosystem image${_NC}"
if [ "$HAVE_GPU" == "yes" ]; then
    echo -e "${_BLUE}HAVE_GPU${_NC}\n"
    sudo docker pull registry.bioturing.com/apps/bioturing-ecosystem:${BBVERSION}
    sudo docker run -t -i \
        -e WEB_DOMAIN="$DOMAIN_NAME" \
        -e BIOTURING_TOKEN="$BIOTURING_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v "$APP_DATA_VOLUME":/data/app_data \
        -v "$USER_DATA_VOLUME":/data/user_data \
        -v "$SSL_VOLUME":/config/ssl \
        --name bioturing \
        --gpus all \
        -d \
        registry.bioturing.com/apps/bioturing-ecosystem:${BBVERSION}
else
    echo -e "${_RED}NO_GPU${_NC}\n"
    sudo docker pull registry.bioturing.com/apps/bioturing-ecosystem-cpu:${BBVERSION}
    sudo docker run -t -i \
        -e WEB_DOMAIN="$DOMAIN_NAME" \
        -e BIOTURING_TOKEN="$BIOTURING_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -p ${HTTP_PORT}:80 \
        -p ${HTTPS_PORT}:443 \
        -v "$APP_DATA_VOLUME":/data/app_data \
        -v "$USER_DATA_VOLUME":/data/user_data \
        -v "$SSL_VOLUME":/config/ssl \
        --name bioturing-cpu \
        -d \
        registry.bioturing.com/apps/bioturing-ecosystem-cpu:${BBVERSION}
fi
