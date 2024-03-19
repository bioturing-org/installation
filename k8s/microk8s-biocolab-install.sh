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

echo -e "${_BLUE}BioTuring ecosystem microk8s installation version${_NC} ${_GREEN}stable${_NC}\n"

read -p "Please enter Bioturing's TOKEN: " BIOCOLAB_TOKEN
if [ -z "$BIOCOLAB_TOKEN" ]; then
    echo -e "${_RED}Can not be empty${_NC}\n"
    exit 1
fi

read -p "Please enter your DOMAIN: " APP_DOMAIN
if [ -z "$APP_DOMAIN" ]; then
    echo -e "${_RED}Can not be empty${_NC}\n"
    exit 1
fi

read -p "Please enter your admin name (admin): " ADMIN_USERNAME
if [ -z "$ADMIN_USERNAME" ]; then
    ADMIN_USERNAME="admin"
fi

read -p "Please enter your admin password (turing2022): " ADMIN_PASSWORD
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="turing2022"
fi
read -p "Confirm admin password (turing2022): " ADMIN_PASSWORD_CONFIRM
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

read -p "Please enter META-DATA PCV's size (5Gi): " METADATA_PVC_SIZE
if [ -z "$METADATA_PVC_SIZE" ]; then
    METADATA_PVC_SIZE="5Gi"
fi


read -p "Please enter USER-DATA PCV's size (5Gi): " USERDATA_PVC_SIZE
if [ -z "$USERDATA_PVC_SIZE" ]; then
    USERDATA_PVC_SIZE="5Gi"
fi

read -p "Please enter APP-DATA PCV's size (5Gi): " APPDATA_PVC_SIZE
if [ -z "$APPDATA_PVC_SIZE" ]; then
    APPDATA_PVC_SIZE="5Gi"
fi


#---------------------------------------------------------------
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

test()
{
#----------------------------------------------------------------
SSLCRT=""
SSLKEY=""
read -p "Use lets-encrypt SSL (must be public your domain), [y, n]: " USELETSENCRYPT
if [ -z "$USELETSENCRYPT" ] || [ "$USELETSENCRYPT" != "y" ]; then
    USELETSENCRYPT="false"

    read -p "Please enter SSL_CRT file: " CRT_PATH
    if [ -z "$CRT_PATH" ]; then
        echo -e "${_RED}Can not be empty${_NC}\n"
        exit 1
    fi

    if [[ -f $CRT_PATH ]]; then 
        SSLCRT=`base64 -w 0 ${CRT_PATH}`
    else
        echo -e "${_RED}Can not find: ${CRT_PATH}${_NC}\n"
        exit 1
    fi

    read -p "Please enter SSL_KEY file: " KEY_PATH
    if [ -z "$KEY_PATH" ]; then
        echo -e "${_RED}Can not be empty${_NC}\n"
        exit 1
    fi

    if [[ -f $CRT_PATH ]]; then 
        SSLKEY=`base64 -w 0 ${KEY_PATH}`
    else
        echo -e "${_RED}Can not find: ${KEY_PATH}${_NC}\n"
        exit 1
    fi
else
    USELETSENCRYPT="true"
fi
#--------------- Above code can be ignored ------------------#
}
#Host IP Address
echo "[INFO] Get LAN IP addresses"
ifconfig -a
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

echo -e "\n HTTP_SERVER_PORT : $HTTP_PORT"
echo -e "\n HTTPS_SERVER_PORT : $HTTPS_PORT"
echo -e "\n METADATA_DIR : ${METADATA_DIR}"
echo -e "\n POSTGRES_PASSWORD : $PG_PASSWORD"
echo -e "\n APP_DOMAIN : $APP_DOMAIN"
echo -e "\n HOST: $HOST"
echo -e "\n REDIS_PASSWORD:  $REDIS_PASSWORD"

# Need install NFS server
NFS_PORT_MAP=""
read -p "Install NFS server [y, n]: " AGREE_NFS
if [ -z "$AGREE_NFS" ] || [ "$AGREE_NFS" != "y" ]; then
    NFS_PORT_MAP=""
else
    NFS_PORT_MAP="-p 111:111"
fi

read -p "Please enter K8S namespace (default): " K8S_NAMESPACE
if [ -z "$K8S_NAMESPACE" ]; then
    K8S_NAMESPACE=""
fi

# Input GPU
read -p "Do you have GPU on your machine: [y/n]" HAVE_GPU
if [ -z "$HAVE_GPU" ] || [ "$HAVE_GPU" != "y" ];
then
    HAVE_GPU="no"
else
echo -e "${_BLUE}Enable GPU operator${_NC}\n"
microk8s enable gpu
fi
read -p "Please enter BioStudio Colab Proxy's VERSION (1.0.27): " COLAB_PROXY_VERSION
if [ -z "$COLAB_PROXY_VERSION" ]; then
    COLAB_PROXY_VERSION="1.0.27"
fi

read -p "Please enter BioStudio Colab VERSION (2.0.50): " COLAB_BIOCOLAB_VERSION
if [ -z "$COLAB_BIOCOLAB_VERSION" ]; then
    COLAB_BIOCOLAB_VERSION="2.0.50"
fi



# Log in to registry.bioturing.com
echo -e "${_BLUE}Logging in to registry.bioturing.com${_NC}"
microk8s helm3 registry login -u admin registry.bioturing.com

echo -e "${_BLUE}Add BioTuring Helm charts to microk8s service${_NC}\n"
microk8s helm3 repo add bioturing https://bioturing.github.io/charts/apps/
microk8s helm3 repo update


# Installing Bioproxy
#--------------------
echo -e "${_BLUE}Install BioTuring Colab Proxy and Biocolab to microk8s service${_NC}\n"
if [ -z "$K8S_NAMESPACE" ]; then
        microk8s helm3 upgrade --install --set secret.data.cbtoken="${BIOCOLAB_TOKEN}" \
            --set secret.data.domain="${APP_DOMAIN}" \
            --set secret.postgresql.dbhub="${PG_HUB_DATABASE}" \
            --set secret.postgresql.username="${PG_USERNAME}" \
            --set secret.postgresql.password="${PG_PASSWORD}" \
            --set secret.server.redis_password="${REDIS_PASSWORD}" \
            --set service.ports.bioproxy.http.port="${HTTP_PORT}" \
            --set service.ports.bioproxy.https.port="${HTTPS_PORT}" \
            --set secret.server.debug_mode="false" \
            --set secret.server.enable_https="false" \
            --set secret.server.use_letsencrypt="false" \
            --set secret.server.colab_list_server="${HOST}:11123" \
            --set service.ports.bioproxy.http.port=${HTTP_PORT} \
            --set service.ports.bioproxy.https.port=${HTTPS_PORT} \
            --set service.ports.bioproxy.postgresql.port=5432 \
            --set service.ports.bioproxy.memcached.port=11211 \
            --set service.ports.bioproxy.redis.port=6379 \
            --set service.ports.bioproxy.minio.port=9090 \
            --set service.ports.bioproxy.minioconsole.port=9091 \
            --set service.ports.bioproxy.ntfsp2.port=2049 ${NFS_PORT_MAP} \
            --set service.ports.bioproxy.ntfsp3.port=32767 \
            --set service.ports.bioproxy.ntfsp4.port=32765 \
            --set persistence.dirs.metadata.size=${METADATA_PVC_SIZE} \
            --set persistence.dirs.user.size=${USERDATA_PVC_SIZE} \
            --set persistence.dirs.app.size=${APPDATA_PVC_SIZE} \
            bioturing bioturing/bioproxy: --version ${COLAB_PROXY_VERSION}

            # install Biocolab
            #------------------

        microk8s helm3 upgrade --install --set secret.data.cbtoken="${BIOCOLAB_TOKEN}" \
            --set APP_DOMAIN_URL="${APP_DOMAIN}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set app_host="0.0.0.0" \
            --set service.ports.biocolab.http.port ="11123" \
            --set secret.postgresql.dbcolab="${PG_DATABASE}" \
            --set secret.postgresql.username="${PG_USERNAME}" \
            --set secret.postgresql.password="${PG_PASSWORD}" \
            --set service.ports.bioproxy.postgresql.port=5432 \
            --set secret.server.redis_password="${REDIS_PASSWORD}" \
            --set secret.server.collaborative_mode="false" \
            --set secret.server.trakfik_proxy_mode="false" \
            --set secret.server.tracing_mode="false" \
            --set secret.server.use_redis_cache="true" \
            --set secret.server.redis_list="$app_host:6379" \
            --set secret.server.memcached_list="$app_host:11211" \
            --set secret.server.mqtt_list_ips="$app_host" \
            --set secret.server.hub_list_ips="$app_host" \
            --set secret.server.aria2c_list_ips="$app_host" \
            --set service.ports.biocolab.http.port=11123 \
            --set service.ports.biocolab.notebook.port=18000 \
            --set service.ports.biocolab.mqttweb.port=9001 \
            --set service.ports.biocolab.mqtttcp.port:1883 \
            --set service.ports.biocolab.jobqueue.port:11300 \
            --set service.ports.biocolab.aria2c.port:6800 \
            --set persistence.dirs.app.size=${APPDATA_PVC_SIZE} \
            --set persistence.dirs.user.size=${USERDATA_PVC_SIZE} \   
            bioturing bioturing/biocolab: --version ${COLAB_BIOCOLAB_VERSION}
    else
        microk8s helm3 upgrade --install --set secret.data.cbtoken="${BIOCOLAB_TOKEN}" \
            --set secret.data.domain="${APP_DOMAIN}" \
            --set secret.postgresql.dbhub="${PG_HUB_DATABASE}" \
            --set secret.postgresql.username="${PG_USERNAME}" \
            --set secret.postgresql.password="${PG_PASSWORD}" \
            --set secret.server.redis_password="${REDIS_PASSWORD}" \
            --set service.ports.bioproxy.http.port="${HTTP_PORT}" \
            --set service.ports.bioproxy.https.port="${HTTPS_PORT}" \
            --set secret.server.debug_mode="false" \
            --set secret.server.enable_https="false" \
            --set secret.server.use_letsencrypt="false" \
            --set secret.server.colab_list_server="${HOST}:11123" \
            --set service.ports.bioproxy.http.port=${HTTP_PORT} \
            --set service.ports.bioproxy.https.port=${HTTPS_PORT} \
            --set service.ports.bioproxy.postgresql.port=5432 \
            --set service.ports.bioproxy.memcached.port=11211 \
            --set service.ports.bioproxy.redis.port=6379 \
            --set service.ports.bioproxy.minio.port=9090 \
            --set service.ports.bioproxy.minioconsole.port=9091 \
            --set service.ports.bioproxy.ntfsp2.port=2049 ${NFS_PORT_MAP} \
            --set service.ports.bioproxy.ntfsp3.port=32767 \
            --set service.ports.bioproxy.ntfsp4.port=32765 \
            --set persistence.dirs.metadata.size=${METADATA_PVC_SIZE} \
            --set persistence.dirs.user.size=${USERDATA_PVC_SIZE} \
            --set persistence.dirs.app.size=${APPDATA_PVC_SIZE} \
            --namespace ${K8S_NAMESPACE} \
            bioturing bioturing/bioproxy: --version ${COLAB_PROXY_VERSION} 

            # install Biocolab
            #-----------------

        microk8s helm3 upgrade --install --set secret.data.cbtoken="${BIOCOLAB_TOKEN}" \
            --set APP_DOMAIN_URL="${APP_DOMAIN}" \
            --set secret.admin.username="${ADMIN_USERNAME}" \
            --set secret.admin.password="${ADMIN_PASSWORD}" \
            --set app_host="0.0.0.0" \
            --set service.ports.biocolab.http.port ="11123" \
            --set secret.postgresql.dbcolab="${PG_DATABASE}" \
            --set secret.postgresql.username="${PG_USERNAME}" \
            --set secret.postgresql.password="${PG_PASSWORD}" \
            --set service.ports.bioproxy.postgresql.port=5432 \
            --set secret.server.redis_password="${REDIS_PASSWORD}" \
            --set secret.server.collaborative_mode="false" \
            --set secret.server.trakfik_proxy_mode="false" \
            --set secret.server.tracing_mode="false" \
            --set secret.server.use_redis_cache="true" \
            --set secret.server.redis_list="$app_host:6379" \
            --set secret.server.memcached_list="$app_host:11211" \
            --set secret.server.mqtt_list_ips="$app_host" \
            --set secret.server.hub_list_ips="$app_host" \
            --set secret.server.aria2c_list_ips="$app_host" \
            --set service.ports.biocolab.http.port=11123 \
            --set service.ports.biocolab.notebook.port=18000 \
            --set service.ports.biocolab.mqttweb.port=9001 \
            --set service.ports.biocolab.mqtttcp.port:1883 \
            --set service.ports.biocolab.jobqueue.port:11300 \
            --set service.ports.biocolab.aria2c.port:6800 \
            --set persistence.dirs.app.size=${APPDATA_PVC_SIZE} \
            --set persistence.dirs.user.size=${USERDATA_PVC_SIZE} \   
            bioturing bioturing/biocolab: --version ${COLAB_BIOCOLAB_VERSION} \
            --create-namespace
fi

