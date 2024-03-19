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

echo -e "${_BLUE}BioProxy standalone installation proces started on Ubuntu Machine.${_NC}\n"
echo -e "${_GREEN}Please do not create folder structure again, if already exist from previous installation.${_NC}\n"

# Input Postgres + REDIS variable
#---------------------------------

PG_DATABASE="biocolab"
PG_HUB_DATABASE="biocohub"
PG_USERNAME="postgres"
PG_PASSWORD="710e93bd11212cea938d87afcc1227e3"
REDIS_PASSWORD="ca39c850e2d845202839be08e8684e4f"

#---------------------------------
# Input HTTP_PROXY , HTTPS_PROXY AND NO_PROXY
echo -e "\n"
read -p "HTTP_PROXY: " HTTP_PROXY
if [ -z "$HTTP_PROXY" ];
then
    HTTP_PROXY=""
fi

echo -e "\n"
read -p "HTTPS_PROXY: " HTTPS_PROXY
if [ -z "$HTTPS_PROXY" ];
then
    HTTPS_PROXY=""
fi

echo -e "\n"
read -p "NO_PROXY: " NO_PROXY
if [ -z "$NO_PROXY" ];
then
    NO_PROXY="localhost,fc00::/7,.svc,kubernetes,127.0.0.1,10.0.0.0/8,10.42.0.90,.local,fe80::/10,192.168.10.0/24,.cluster.local,::1/128,.default,0.0.0.0"
fi

# Input metadata volume using bioproxy => /bitnami/postgresql
echo -e "\n"
read -p "Press Enter if already exist. Metadata volume (persistent volume to store metadata /biocolab/metadata --> /bitnami/postgresql): " METADATA_DIR
if [ -z "$METADATA_DIR" ];
then
    METADATA_DIR="/biocolab/metadata"
fi
echo -e "METADATA_DIR=${METADATA_DIR} \n"
if [ ! -d "$METADATA_DIR" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input CONFIG_VOLUME using bioproxy => /home/configs
echo -e "\n"
read -p "Press Enter if already exist. Config volume (this directory must contain two files: tls.crt and tls.key from your SSL certificate for HTTPS /biocolab/configs --> /home/configs): " CONFIG_VOLUME
if [ -z "$CONFIG_VOLUME" ];
then
    CONFIG_VOLUME="/biocolab/configs"
fi
echo -e "CONFIG_VOLUME=${CONFIG_VOLUME} \n"
if [ ! -d "$CONFIG_VOLUME" ];
then
    echo -e "${_RED}Directory DOES NOT exist...${_NC}"
    exit 1
fi

# Input domain name
echo -e "\n"
read -p "Domain name (example: biocolab.<Your Domain>.com. Kindly input your existing domain): " APP_DOMAIN
if [ -z "$APP_DOMAIN" ];
then
    echo -e "${_RED}Empty domain name is not allowed. Exiting...${_NC}"
    exit 1
fi

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

#Host IP Address
echo -e "\n"
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

#----------------------------
# Docker installation confirmation.
# already_install_count=`ps -ef | grep -i docker | grep -v grep | wc -l`

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
#----------------------------

# Check Version
echo -e "\n"
read -p "Please enter Biocolab's Proxy 1.0.27 (latest): " COLAB_PROXY_VERSION
if [ -z "$COLAB_PROXY_VERSION" ]; then
   COLAB_PROXY_VERSION="1.0.27"
   echo -e "\nBioproxy Version: $COLAB_PROXY_VERSION\n"

fi

# Need install NFS server
NFS_PORT_MAP=""
read -p "Install NFS server [y, n]: " AGREE_NFS
if [ -z "$AGREE_NFS" ] || [ "$AGREE_NFS" != "y" ]; then
    NFS_PORT_MAP=""
    echo -e "\nContinue to install Bioproxy without NFS"
else
    count_nfs_port=`netstat -pnlu | grep ':111' | wc -l`
    if [ "$count_nfs_port" -ge "1" ]; then
        echo -e "\nPort is already in used."
        netstat -nlup | grep ':111' 
        echo -e "\nPlease check service and select NO for NFS server"
        exit 1
    else
        NFS_PORT_MAP="-p 2049:2049 -p 111:111"
        sudo apt update
        sudo apt install nfs-common -y
        sudo modprobe nfs || true
        sudo modprobe nfsd || true
    fi
fi


echo -e "\n APP_DOMAIN : $APP_DOMAIN"
echo -e "\n HOST: $HOST"
echo -e "\n POSTGRESQL_DATABASE: $PG_HUB_DATABASE"
echo -e "\n POSTGRESQL_USERNAME : $PG_USERNAME"
echo -e "\n POSTGRES_PASSWORD : $PG_PASSWORD"
echo -e "\n REDIS_PASSWORD:  $REDIS_PASSWORD"
echo -e "\n HTTP_SERVER_PORT : $HTTP_PORT"
echo -e "\n HTTPS_SERVER_PORT : $HTTPS_PORT"
echo -e "\n METADATA_DIR : ${METADATA_DIR}"
echo -e "\n CONFIG VOLUME : ${CONFIG_VOLUME}"
echo -e "\n COLAB_LIST_SERVER : ${HOST}:11123" 

# Login to bioturing.com
echo -e "\n"
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
sudo docker login -u="bioturing" -p="dckr_pat_XMFWkKcfL8p76_NlQzTfBAhuoww"

echo -e "${_BLUE}Pulling bioturing BioProxy - ecosystem image${_NC}"
echo -e "${_BLUE}Logging in to ${_NC}"
BIOPROXY_REPO="bioturing/bioproxy:${COLAB_PROXY_VERSION}"
sudo docker pull ${BIOPROXY_REPO}

## stop and remove previous instance
sudo docker stop bioproxy || true
sudo docker rm bioproxy || true
sudo docker container stop bioproxy || true
sudo docker container rm bioproxy || true

sudo docker run -t -i \
    --add-host ${APP_DOMAIN}:${HOST} \
    -e APP_DOMAIN="$APP_DOMAIN" \
    -e POSTGRESQL_DATABASE="$PG_HUB_DATABASE" \
    -e POSTGRESQL_USERNAME="$PG_USERNAME" \
    -e POSTGRESQL_PASSWORD="$PG_PASSWORD" \
    -e POSTGRESQL_POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRESQL_PORT_NUMBER=5432 \
    -e REDIS_PASSWORD="$REDIS_PASSWORD" \
    -e HTTP_SERVER_PORT="80" \
    -e HTTPS_SERVER_PORT="443" \
    -e MEMCACHED_PORT=11211 \
    -e REDIS_PORT=6379 \
    -e DEBUG_MODE="false" \
    -e ENABLE_HTTPS="true" \
    -e USE_LETSENCRYPT="false" \
    -e MAX_CONNECTION=5000 \
    -e COLAB_LIST_SERVER="$HOST:11123" \
    -p ${HTTP_PORT}:80 \
    -p ${HTTPS_PORT}:443 \
    -p 5432:5432 \
    -p 11211:11211 \
    -p 6379:6379 \
    -p 9091:9091 \
    ${NFS_PORT_MAP} \
    -p 32767:32767 \
    -p 32765:32765 \
    -v ${METADATA_DIR}:/bitnami/postgresql:rw \
    -v ${CONFIG_VOLUME}:/home/configs:rw \
    --name bioproxy \
    --cap-add SYS_ADMIN \
    --cap-add NET_ADMIN \
    --device /dev/fuse \
    --security-opt apparmor:unconfined \
    -d --restart always ${BIOPROXY_REPO}

## stop and start previous instance
#sudo docker stop bioproxy || true
#sudo docker start bioproxy || true
sudo docker stop biocolab || true
sudo docker start biocolab || true
