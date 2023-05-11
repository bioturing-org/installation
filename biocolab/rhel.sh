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

# Cert before install other packages in OS
read -p "Install Self-Signed CA Certificate [y, n]: " AGREE_CA
if [ -z "$AGREE_CA" ] || [ "$AGREE_CA" != "y" ]; then
    sudo yum install curl wget ca-certificates -y
else
    sudo yum install curl wget ca-certificates -y
    echo -e "${_BLUE}Installing trusted SSL certificates${_NC}\n"
    sudo bash ../cert/rhel.sh
fi

# Input BioColab Token
read -p "BioColab token (please contact support@bioturing.com for a token): " BIOCOLAB_TOKEN
if [ -z "$BIOCOLAB_TOKEN" ];
then
    echo -e "${_RED}Empty token. Existing...${_NC}"
    exit 1
fi

# Input domain name
read -p "Domain name (example: biocolab.<Your Domain>.com): " APP_DOMAIN
if [ -z "$APP_DOMAIN" ];
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
read -p "Confirm administrator password: " ADMIN_PASSWORD_CONFIRM
if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ];
then
    echo -e "${_RED}Password does not match. Exiting...${_NC}"
    exit 1
fi

# Input Postgres + REDIS variable
#---------------------------------

PG_DATABASE="biocolab"
PG_HUB_DATABASE="biocohub"
PG_USERNAME="postgres"
PG_PASSWORD="710e93bd11212cea938d87afcc1227e3"
REDIS_PASSWORD="ca39c850e2d845202839be08e8684e4f"

#---------------------------------

# Input metadata volume using bioproxy => /bitnami/postgresql
read -p "Metadata volume (persistent volume to store metadata /bitnami/postgresql): " METADATA_DIR
if [ ! -d "$METADATA_DIR" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input SSL volume using bioproxy => /home/configs
read -p "ssl volume (this directory must contain two files: tls.crt and tls.key from your SSL certificate for HTTPS /home/configs): " SSL_VOLUME
if [ ! -d "$SSL_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist...${_NC}"
    exit 1
fi

# Input user data volume => /home
read -p "user_data volume (persistent volume to store user data /home): " DATA_PATH
if [ ! -d "$DATA_PATH" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input application data volume => /appdata
read -p "app_data volume (persistent volume to store app data /appdata): " APP_PATH
if [ ! -d "$APP_PATH" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
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

# Docker + CUDA
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

# Input GPU
read -p "Do you have GPU on your machine: [y/n]" HAVE_GPU
if [ -z "$HAVE_GPU" ] || [ "$HAVE_GPU" != "y" ];
then
    HAVE_GPU="no"
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

    # NVIDIA CUDA Docker 2
    echo -e "${_BLUE}Installing NVIDIA Docker 2${_NC}\n"
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
    && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    sudo yum clean expire-cache
    sudo yum install -y nvidia-docker2
    sudo systemctl restart docker
fi

# Basic package
echo -e "${_BLUE}Installing base package${_NC}\n"
sudo yum update
sudo yum install net-tools -y

#Host IP Address
echo "[INFO] Get LAN IP addresses"
LIST_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'`
HOST=`echo $LIST_IP | awk -F' ' '{print $NF}'`

echo "Given IP $HOST was detected. Kindly provide ethernet IP. You might have multiple IP's"
read -p "Would you like to change IP[${HOST}] [y, n]: " AGREE_IP_CHANGE
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

# Check Version
read -p "Please enter Biocolab's Proxy 1.0.1 (latest): " COLAB_PROXY_VERSION
if [ -z "$COLAB_PROXY_VERSION" ]; then
    COLAB_VERSION="1.0.1"
fi

echo -e "\n HTTP_SERVER_PORT : $HTTP_PORT"
echo -e "\n HTTPS_SERVER_PORT : $HTTPS_PORT"
echo -e "\n METADATA_DIR : ${METADATA_DIR}"
echo -e "\n POSTGRES_PASSWORD : $PG_PASSWORD"
echo -e "\n APP_DOMAIN : $APP_DOMAIN"
echo -e "\n HOST: $HOST"
echo -e "\n REDIS_PASSWORD:  $REDIS_PASSWORD"

# Login to bioturing.com
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
sudo docker login -u="bioturing" -p="dckr_pat_XMFWkKcfL8p76_NlQzTfBAhuoww"

echo -e "${_BLUE}Pulling bioturing BioColab Proxy - ecosystem image${_NC}"
echo -e "${_BLUE}Logging in to ${_NC}"
BIOPROXY_REPO="bioturing/bioproxy:${COLAB_PROXY_VERSION}"
sudo docker pull ${BIOPROXY_REPO}
sudo docker run -t -i \
    -e APP_DOMAIN="$APP_DOMAIN" \
    -e POSTGRESQL_DATABASE="$PG_HUB_DATABASE" \
    -e POSTGRESQL_USERNAME="$PG_USERNAME" \
    -e POSTGRESQL_PASSWORD="$PG_PASSWORD" \
    -e POSTGRESQL_POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRESQL_PORT_NUMBER=5432 \
    -e REDIS_PASSWORD="$REDIS_PASSWORD" \
    -e HTTP_SERVER_PORT="$HTTP_PORT" \
    -e HTTPS_SERVER_PORT="$HTTPS_PORT" \
    -e MEMCACHED_PORT=11211 \
    -e REDIS_PORT=6379 \
    -e DEBUG_MODE="false" \
    -e ENABLE_HTTPS="false" \
    -e USE_LETSENCRYPT="false" \
    -e COLAB_LIST_SERVER="$HOST:11123" \
    -p ${HTTP_PORT}:80 \
    -p ${HTTPS_PORT}:443 \
    -p 5432:5432 \
    -p 11211:11211 \
    -p 6379:6379 \
    -p 9090:9090 \
    -p 9091:9091 \
    -p 111:111 \
    -p 2049:2049 \
    -p 32767:32767 \
    -p 32765:32765 \
    -v ${METADATA_DIR}:/bitnami/postgresql \
    -v ${SSL_VOLUME}:/home/configs \
    --name bioproxy \
    --cap-add SYS_ADMIN  \
    --cap-add NET_ADMIN  \
    -d ${BIOPROXY_REPO}

echo "Sleep 120 seconds to wait the bioproxy finish to start"
sleep 120

###################################################################################

# Check Version
read -p "Please enter Biocolab's VERSION 1.0.1 (latest): " COLAB_VERSION
if [ -z "$COLAB_VERSION" ]; then
    COLAB_VERSION="1.0.1"
fi

# Login to bioturing.com
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
sudo docker login -u="bioturing" -p="dckr_pat_XMFWkKcfL8p76_NlQzTfBAhuoww"

BIOCOLAB_REPO="bioturing/biocolab:${COLAB_VERSION}"
sudo docker pull ${BIOCOLAB_REPO}

# Pull BioTuring ecosystem
echo -e "${_BLUE}Pulling bioturing ecosystem image${_NC}"
if [ "$HAVE_GPU" == "yes" ]; then
    echo -e "${_BLUE}HAVE_GPU${_NC}\n"
    sudo docker run -t -i \
        -e APP_DOMAIN_URL="$APP_DOMAIN" \
        -e COLAB_TOKEN="$BIOCOLAB_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e PG_HOST="$HOST" \
        -e PG_DATABASE="$PG_DATABASE" \
        -e PG_USERNAME="$PG_USERNAME" \
        -e PG_PASSWORD="$PG_PASSWORD" \
        -e PG_PORT=5432 \
        -e REDIS_PASSWORD="$REDIS_PASSWORD" \
        -e COLLABORATIVE_MODE="false" \
        -e TRAEFIK_PROXY_MODE="false" \
        -e TRACING_MODE="false" \
        -e USE_REDIS_CACHE="true" \
        -e REDIS_LIST="$HOST:6379" \
        -e MEMCACHED_LIST="$HOST:11211" \
        -e MQTT_LIST_IPS="$HOST" \
        -e HUB_LIST_IPS="$HOST" \
        -e ARIA2C_LIST_IPS="$HOST" \
        -p 11123:11123 \
        -p 18000:18000 \
        -p 9001:9001 \
        -p 1883:1883 \
        -p 11300:11300 \
        -p 6800:6800 \
        -v "$APP_PATH":/appdata \
        -v "$DATA_PATH":/home \
        --name biocolab \
        --gpus all \
        --cap-add SYS_ADMIN  \
        --cap-add NET_ADMIN  \
        -d ${BIOCOLAB_REPO}
else
echo -e "${_RED}NO_GPU${_NC}\n"
    sudo docker run -t -i \
        -e APP_DOMAIN_URL="$APP_DOMAIN" \
        -e COLAB_TOKEN="$BIOCOLAB_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e PG_HOST="$HOST" \
        -e PG_DATABASE="$PG_DATABASE" \
        -e PG_USERNAME="$PG_USERNAME" \
        -e PG_PASSWORD="$PG_PASSWORD" \
        -e PG_PORT=5432 \
        -e REDIS_PASSWORD="$REDIS_PASSWORD" \
        -e COLLABORATIVE_MODE="false" \
        -e TRAEFIK_PROXY_MODE="false" \
        -e TRACING_MODE="false" \
        -e USE_REDIS_CACHE="true" \
        -e REDIS_LIST="$HOST:6379" \
        -e MEMCACHED_LIST="$HOST:11211" \
        -e MQTT_LIST_IPS="$HOST" \
        -e HUB_LIST_IPS="$HOST" \
        -e ARIA2C_LIST_IPS="$HOST" \
        -p 11123:11123 \
        -p 18000:18000 \
        -p 9001:9001 \
        -p 1883:1883 \
        -p 11300:11300 \
        -p 6800:6800 \
        -v "$APP_PATH":/appdata \
        -v "$DATA_PATH":/home \
        --name biocolab \
        --cap-add SYS_ADMIN  \
        --cap-add NET_ADMIN  \
        -d ${BIOCOLAB_REPO}
fi