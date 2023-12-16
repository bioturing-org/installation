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

echo -e "${_BLUE}BioColab RedHat installation version${_NC} ${_GREEN}stable${_NC}\n"
echo -e "\n"

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
read -p "Metadata volume (persistent volume to store metadata /biocolab/metadata --> /bitnami/postgresql): " METADATA_DIR
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
read -p "config volume (this directory must contain two files: tls.crt and tls.key from your SSL certificate for HTTPS /biocolab/configs --> /home/configs): " CONFIG_VOLUME
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

# Input user data volume => /home
echo -e "\n"
read -p "user_data volume (persistent volume to store user data /biocolab/userdata --> /home): " USERDATA_PATH
if [ -z "$USERDATA_PATH" ];
then
    USERDATA_PATH="/biocolab/userdata"
fi
echo -e "USERDATA_PATH=${USERDATA_PATH} \n"
if [ ! -d "$USERDATA_PATH" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input application data volume => /appdata
echo -e "\n"
read -p "app_data volume (persistent volume to store app data /biocolab/appdata --> /appdata): " APP_PATH
if [ -z "$APP_PATH" ];
then
    APP_PATH="/biocolab/appdata"
fi
echo -e "APP_PATH=${APP_PATH} \n"
if [ ! -d "$APP_PATH" ];
then
    echo -e "${_RED}Directory DOES NOT exist. Exiting...${_NC}"
    exit 1
fi

# Input BioColab Token
echo -e "\n"
read -p "BioColab token (please contact support@bioturing.com for a token): " BIOCOLAB_TOKEN
if [ -z "$BIOCOLAB_TOKEN" ];
then
    echo -e "${_RED}Empty token. Existing...${_NC}"
    exit 1
fi

# Input domain name
echo -e "\n"
read -p "Domain name (example: biocolab.<Your Domain>.com): " APP_DOMAIN
if [ -z "$APP_DOMAIN" ];
then
    echo -e "${_RED}Empty domain name is not allowed. Exiting...${_NC}"
    exit 1
fi

# Input administrator username
# echo -e "\n"
# read -p "Administrator username (example: admin): " ADMIN_USERNAME
# if [ -z "$ADMIN_USERNAME" ];
# then
#    echo -e "${_RED}Empty administrator username is not allowed. Exiting...${_NC}"
#    exit 1
#fi
# Admin user name
ADMIN_USERNAME="admin"

echo -e "\nPlease note user name: $ADMIN_USERNAME"

# Input administrator password
echo -e "\n"
read -s -p "Administrator password: " ADMIN_PASSWORD
if [ -z "$ADMIN_PASSWORD" ];
then
    echo -e "${_RED}Empty administrator password is not allowed. Exiting...${_NC}"
    exit 1
fi

# Confirm administrator password
echo -e "\n"
read -s -p "Confirm administrator password: " ADMIN_PASSWORD_CONFIRM
if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ];
then
    echo -e "${_RED}Password does not match. Exiting...${_NC}"
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


read -p "Do you have GPU on your machine: [y/n]" HAVE_GPU
if [ -z "$HAVE_GPU" ] || [ "$HAVE_GPU" != "y" ];
then
    HAVE_GPU="no"
else
    HAVE_GPU="yes"
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

# Check Version
echo -e "\n"
read -p "Please enter Biocolab's Proxy 1.0.26 (latest): " COLAB_PROXY_VERSION
if [ -z "$COLAB_PROXY_VERSION" ]; then
   COLAB_PROXY_VERSION="1.0.26"
fi


echo -e "\n HTTP_SERVER_PORT : $HTTP_PORT"
echo -e "\n HTTPS_SERVER_PORT : $HTTPS_PORT"
echo -e "\n METADATA_DIR : ${METADATA_DIR}"
echo -e "\n POSTGRES_PASSWORD : $PG_PASSWORD"
echo -e "\n APP_DOMAIN : $APP_DOMAIN"
echo -e "\n HOST: $HOST"
echo -e "\n REDIS_PASSWORD:  $REDIS_PASSWORD"

# Login to bioturing.com
echo -e "\n"
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
sudo docker login -u="bioturing" -p="dckr_pat_XMFWkKcfL8p76_NlQzTfBAhuoww"

echo -e "${_BLUE}Pulling bioturing BioColab Proxy - ecosystem image${_NC}"
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
    -e ENABLE_HTTPS="false" \
    -e USE_LETSENCRYPT="false" \
    -e MAX_CONNECTION=5000 \
    -e COLAB_LIST_SERVER="$HOST:11123" \
    -p ${HTTP_PORT}:80 \
    -p ${HTTPS_PORT}:443 \
    -p 5432:5432 \
    -p 11211:11211 \
    -p 6379:6379 \
    -p 9091:9091 \
    -p 2049:2049 ${NFS_PORT_MAP} \
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

echo "Sleep 120 seconds to wait the bioproxy finish to start"
sleep 120

###################################################################################

# Check Version
echo -e "\n"
read -p "Please enter Biocolab's VERSION 2.0.50 (latest): " COLAB_VERSION
if [ -z "$COLAB_VERSION" ]; then
    COLAB_VERSION="2.0.50"
fi

# Login to bioturing.com
echo -e "\n"
echo -e "${_BLUE}Logging in to bioturing.com${_NC}"
sudo docker login -u="bioturing" -p="dckr_pat_XMFWkKcfL8p76_NlQzTfBAhuoww"

BIOCOLAB_REPO="bioturing/biocolab:${COLAB_VERSION}"
sudo docker pull ${BIOCOLAB_REPO}

## stop and remove previous instance
sudo docker stop biocolab || true
sudo docker rm biocolab || true
sudo docker container stop biocolab || true
sudo docker container rm biocolab || true

# Pull BioTuring ecosystem
echo -e "${_BLUE}Pulling bioturing ecosystem image${_NC}"
if [ "$HAVE_GPU" == "y" ] || [ "$HAVE_GPU" == "yes" ]; then
    echo -e "${_BLUE}HAVE_GPU${_NC}\n"
    sudo docker run -t -i \
        --add-host ${APP_DOMAIN}:${HOST} \
        -e APP_DOMAIN_URL="https://${APP_DOMAIN}" \
        -e COLAB_TOKEN="$BIOCOLAB_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e HOST="0.0.0.0" \
        -e PORT="11123" \
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
        -e NO_PROXY="$NO_PROXY" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e no_proxy="$NO_PROXY" \
        -e http_proxy="$HTTP_PROXY" \
        -e https_proxy="$HTTPS_PROXY" \
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
        -v $APP_PATH:/appdata:rw \
        -v $USERDATA_PATH:/home:rw \
        --name biocolab \
        --gpus all \
        --cap-add SYS_ADMIN \
        --cap-add NET_ADMIN \
        --device /dev/fuse \
        --security-opt apparmor:unconfined \
        -d --restart always ${BIOCOLAB_REPO}
else
    echo -e "${_RED}NO_GPU${_NC}\n"
    sudo docker run -t -i \
        --add-host ${APP_DOMAIN}:${HOST} \
        -e APP_DOMAIN_URL="https://${APP_DOMAIN}" \
        -e COLAB_TOKEN="$BIOCOLAB_TOKEN" \
        -e ADMIN_USERNAME="$ADMIN_USERNAME" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e HOST="0.0.0.0" \
        -e PORT="11123" \
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
        -e NO_PROXY="$NO_PROXY" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e no_proxy="$NO_PROXY" \
        -e http_proxy="$HTTP_PROXY" \
        -e https_proxy="$HTTPS_PROXY" \
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
        -v $APP_PATH:/appdata:rw \
        -v $USERDATA_PATH:/home:rw \
        --name biocolab \
        --cap-add SYS_ADMIN \
        --cap-add NET_ADMIN \
        --device /dev/fuse \
        --security-opt apparmor:unconfined \
        -d --restart always ${BIOCOLAB_REPO}
fi
